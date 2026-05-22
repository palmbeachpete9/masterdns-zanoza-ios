// Package mobile exposes a narrow, gomobile-bindable surface for the
// MasterDnsVPN client. Used by the Zanoza iOS / macOS app.
package mobile

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"sync"

	"masterdnsvpn-go/internal/client"
	"masterdnsvpn-go/internal/config"
)

// LogWriter receives one log line at a time (no trailing newline).
type LogWriter interface {
	WriteLog(line string)
}

var (
	mu         sync.Mutex
	cancelFn   context.CancelFunc
	runningWG  sync.WaitGroup
	stdoutPump *stdoutInterceptor
	writerRef  LogWriter
)

// SetLogWriter installs a writer that will receive both stdout lines emitted
// by the Go client (logger, banners) and any error/diagnostic messages from
// this shim. Pass nil to disable forwarding.
func SetLogWriter(w LogWriter) {
	mu.Lock()
	defer mu.Unlock()
	writerRef = w
}

// IsRunning reports whether a Start call is currently active.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return cancelFn != nil
}

// Start launches the MasterDnsVPN client with the given TOML config and
// newline-delimited resolver list. runtimeDir is a writable directory where
// transient files (config copies, dns cache) will live.
//
// Returns immediately once the client has been bootstrapped. The tunnel
// continues running in a background goroutine until Stop is called.
func Start(configTOML, resolversText, runtimeDir string) error {
	mu.Lock()
	if cancelFn != nil {
		mu.Unlock()
		return errors.New("client already running")
	}
	mu.Unlock()

	if runtimeDir == "" {
		return errors.New("runtimeDir is required")
	}
	if err := os.MkdirAll(runtimeDir, 0o755); err != nil {
		return fmt.Errorf("create runtime dir: %w", err)
	}

	configPath := filepath.Join(runtimeDir, "client_config.toml")
	resolversPath := filepath.Join(runtimeDir, "client_resolvers.txt")
	if err := os.WriteFile(configPath, []byte(configTOML), 0o600); err != nil {
		return fmt.Errorf("write client_config.toml: %w", err)
	}
	if err := os.WriteFile(resolversPath, []byte(resolversText), 0o600); err != nil {
		return fmt.Errorf("write client_resolvers.txt: %w", err)
	}

	pump := newStdoutInterceptor(func(line string) {
		mu.Lock()
		w := writerRef
		mu.Unlock()
		if w != nil {
			w.WriteLog(line)
		}
	})
	if err := pump.start(); err != nil {
		return fmt.Errorf("install stdout interceptor: %w", err)
	}

	overrides := config.ClientConfigOverrides{Values: map[string]any{}}
	app, err := client.Bootstrap(configPath, "", overrides)
	if err != nil {
		pump.stop()
		return fmt.Errorf("bootstrap: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	mu.Lock()
	cancelFn = cancel
	stdoutPump = pump
	mu.Unlock()

	runningWG.Add(1)
	go func() {
		defer runningWG.Done()
		defer func() {
			if r := recover(); r != nil {
				emit(fmt.Sprintf("client panic: %v\n%s", r, debug.Stack()))
			}
		}()
		if err := app.Run(ctx); err != nil {
			emit(fmt.Sprintf("client runtime error: %v", err))
		}
	}()

	emit("Zanoza tunnel started.")
	return nil
}

// Stop signals the running client to exit and waits briefly for shutdown.
// Safe to call when the client is not running.
func Stop() {
	mu.Lock()
	cancel := cancelFn
	pump := stdoutPump
	cancelFn = nil
	stdoutPump = nil
	mu.Unlock()

	if cancel == nil {
		return
	}
	cancel()
	runningWG.Wait()
	if pump != nil {
		pump.stop()
	}
	emit("Zanoza tunnel stopped.")
}

func emit(line string) {
	mu.Lock()
	w := writerRef
	mu.Unlock()
	if w != nil {
		w.WriteLog(line)
	}
}
