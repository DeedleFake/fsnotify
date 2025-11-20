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

const ok = `"ok"`

func sendData[T string | []byte](id uint64, buf T) {
	err := binary.Write(os.Stdout, binary.BigEndian, uint16(8+len(buf)))
	if err != nil {
		panic(err)
	}

	err = binary.Write(os.Stdout, binary.BigEndian, id)
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

func sendMessage(id uint64, msg any) {
	data, err := json.Marshal(msg)
	if err != nil {
		panic(err)
	}
	sendData(id, data)
}

func sendError(id uint64, err error) {
	type errorData struct {
		Err string
	}
	data, err := json.Marshal(errorData{Err: err.Error()})
	if err != nil {
		panic(err)
	}
	sendData(id, data)
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
			sendMessage(0, event)

		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			sendError(0, err)
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
		id := binary.BigEndian.Uint64(unsafe.Slice(unsafe.StringData(cmd), len(cmd)))

		cmd, arg, _ := strings.Cut(cmd[8:], " ")
		switch cmd {
		case "add_watch":
			err := watcher.Add(arg)
			if err != nil {
				sendError(id, err)
				continue
			}
			sendData(id, ok)

		case "remove":
			err := watcher.Remove(arg)
			if err != nil {
				sendError(id, err)
				continue
			}
			sendData(id, ok)

		default:
			panic(fmt.Errorf("unknown command: %q", cmd))
		}
	}
}
