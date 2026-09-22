package main

import (
	"io"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/pong", func(response http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(response, "Pong")
	})
	log.Println("Go server listening on http://127.0.0.1:8080")
	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
