package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json/v2"
	"fmt"
	"io"
	"iter"
	"os"
	"os/signal"
	"strings"
	"unsafe"

	"github.com/fsnotify/fsnotify"
)

func sendData[T string | []byte](buf T) {
	err := binary.Write(os.Stdout, binary.BigEndian, uint16(len(buf)))
	if err != nil {
		panic(err)
	}

	switch buf := any(buf).(type) {
	case []byte:
		_, err = os.Stdout.Write(buf)
	case string:
		_, err = os.Stdout.WriteString(buf)
	}
	if err != nil {
		panic(err)
	}
}

func sendEvent(ev fsnotify.Event) {
	data, err := json.Marshal(ev)
	if err != nil {
		panic(err)
	}
	sendData(data)
}

func sendError(err error) {
	type errorData struct {
		Err string
	}
	data, err := json.Marshal(errorData{Err: err.Error()})
	if err != nil {
		panic(err)
	}
	sendData(data)
}

func commands() iter.Seq[string] {
	return func(yield func(string) bool) {
		for {
			var size uint16
			err := binary.Read(os.Stdin, binary.BigEndian, &size)
			if err != nil {
				panic(err)
			}

			buf := make([]byte, size)
			_, err = io.ReadFull(os.Stdin, buf)
			if err != nil {
				panic(err)
			}

			str := unsafe.String(unsafe.SliceData(buf), len(buf))
			if !yield(str) {
				return
			}
		}
	}
}

func watch(ctx context.Context, watcher *fsnotify.Watcher) {
	var buf bytes.Buffer

	for {
		select {
		case <-ctx.Done():
			return

		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			sendEvent(event)

		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			sendError(err)
		}

		buf.Reset()
	}
}

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		panic(err)
	}
	defer watcher.Close()
	go watch(ctx, watcher)

	for cmd := range commands() {
		cmd, arg, _ := strings.Cut(cmd, " ")
		switch cmd {
		case "add_watch":
			err := watcher.Add(arg)
			if err != nil {
				// TODO: Send errors to Elixir.
				panic(err)
			}

		case "remove":
			err := watcher.Remove(arg)
			if err != nil {
				panic(err)
			}

		default:
			panic(fmt.Errorf("unknown command: %q", cmd))
		}
	}
}
