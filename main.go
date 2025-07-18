package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

type PingMessage struct {
	Type      string `json:"type"`
	Signature string `json:"signature"`
	Timestamp string `json:"timestamp"`
}

type PongMessage struct {
	Type       string `json:"type"`
	Status     string `json:"status,omitempty"`
	Error      string `json:"error,omitempty"`
	Timestamp  string `json:"timestamp"`
	ServerTime string `json:"server_time,omitempty"`
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		// Allow all origins for CORS
		return true
	},
}

// Global variable for TLS state
var useTLS bool

func generateSignature(date string) string {
	data := date + "ming-mong-server"
	hash := sha256.Sum256([]byte(data))
	return hex.EncodeToString(hash[:])[:16]
}

func isValidSignature(signature string) bool {
	now := time.Now().UTC()

	// Check today's signature
	todayDate := now.Format("2006-01-02")
	todaySignature := generateSignature(todayDate)
	if signature == todaySignature {
		return true
	}

	// Check yesterday's signature (timezone tolerance)
	yesterday := now.Add(-24 * time.Hour)
	yesterdayDate := yesterday.Format("2006-01-02")
	yesterdaySignature := generateSignature(yesterdayDate)
	if signature == yesterdaySignature {
		return true
	}

	return false
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Log connection attempt
	clientIP := r.Header.Get("X-Real-IP")
	if clientIP == "" {
		clientIP = r.Header.Get("X-Forwarded-For")
		if clientIP == "" {
			clientIP = strings.Split(r.RemoteAddr, ":")[0]
		}
	}

	log.Printf("WebSocket connection from %s", clientIP)

	// Upgrade to WebSocket
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	// Set read deadline (5 second timeout)
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))

	// Read message
	_, messageBytes, err := conn.ReadMessage()
	if err != nil {
		log.Printf("Error reading message: %v", err)
		return
	}

	// Parse JSON message
	var pingMsg PingMessage
	if err := json.Unmarshal(messageBytes, &pingMsg); err != nil {
		log.Printf("Invalid JSON format from %s", clientIP)

		// Send error response
		errorMsg := PongMessage{
			Type:      "error",
			Error:     "invalid_format",
			Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		}

		if jsonData, err := json.Marshal(errorMsg); err == nil {
			conn.WriteMessage(websocket.TextMessage, jsonData)
		}
		return
	}

	// Check message type
	if pingMsg.Type != "ping" {
		log.Printf("Invalid message type '%s' from %s", pingMsg.Type, clientIP)

		// Send error response
		errorMsg := PongMessage{
			Type:      "error",
			Error:     "invalid_type",
			Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		}

		if jsonData, err := json.Marshal(errorMsg); err == nil {
			conn.WriteMessage(websocket.TextMessage, jsonData)
		}
		return
	}

	// Validate signature
	if !isValidSignature(pingMsg.Signature) {
		log.Printf("Invalid signature from %s: %s", clientIP, pingMsg.Signature)

		// Send error response
		errorMsg := PongMessage{
			Type:      "error",
			Error:     "invalid_signature",
			Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		}

		if jsonData, err := json.Marshal(errorMsg); err == nil {
			conn.WriteMessage(websocket.TextMessage, jsonData)
		}
		return
	}

	// Valid signature - send pong
	log.Printf("Valid ping from %s", clientIP)

	now := time.Now().UTC()
	pongMsg := PongMessage{
		Type:       "pong",
		Status:     "ok",
		Timestamp:  now.Format(time.RFC3339Nano),
		ServerTime: now.Format(time.RFC3339Nano),
	}

	if jsonData, err := json.Marshal(pongMsg); err == nil {
		conn.WriteMessage(websocket.TextMessage, jsonData)
	}
}

func main() {
	// Get port from environment variable
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Get TLS settings from environment variables
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")
	enableTLS := os.Getenv("ENABLE_TLS")

	// Validate port
	if portNum, err := strconv.Atoi(port); err != nil || portNum < 1 || portNum > 65535 {
		log.Fatalf("Invalid port: %s", port)
	}

	// Setup WebSocket handler
	http.HandleFunc("/ws", handleWebSocket)

	// Add HTTP ping endpoint for non-TLS compatibility
	http.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		// Handle CORS preflight request
		if r.Method == http.MethodOptions {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "X-Ping-Signature")
			w.Header().Set("Access-Control-Max-Age", "86400")
			w.WriteHeader(http.StatusNoContent)
			return
		}

		// Only allow GET requests
		if r.Method != http.MethodGet {
			if hijacker, ok := w.(http.Hijacker); ok {
				conn, _, err := hijacker.Hijack()
				if err == nil {
					conn.Close()
				}
			}
			return
		}

		// Get signature from header
		signature := r.Header.Get("X-Ping-Signature")
		if signature == "" {
			if hijacker, ok := w.(http.Hijacker); ok {
				conn, _, err := hijacker.Hijack()
				if err == nil {
					conn.Close()
				}
			}
			return
		}

		// Validate signature
		if !isValidSignature(signature) {
			if hijacker, ok := w.(http.Hijacker); ok {
				conn, _, err := hijacker.Hijack()
				if err == nil {
					conn.Close()
				}
			}
			return
		}

		// Valid signature - respond with CORS headers
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET")
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})

	// Add certificate acceptance endpoint for TLS
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			// If TLS is enabled, serve a simple page for certificate acceptance
			if useTLS {
				w.Header().Set("Content-Type", "text/html")
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(`<!DOCTYPE html>
<html>
<head>
    <title>Ming-Mong Server - Certificate Accepted</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .container { max-width: 600px; margin: 0 auto; }
        .success { color: #28a745; }
        .info { color: #17a2b8; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🔒 Ming-Mong Server</h1>
        <h2>Certificate Accepted Successfully!</h2>
        <p class="info">Your browser now trusts this server's certificate.</p>
        <p>WebSocket endpoint: <strong>wss://` + r.Host + `/ws</strong></p>
        <p>HTTP endpoint: <strong>https://` + r.Host + `/ping</strong></p>
        <p>You can now close this tab and use HTTPS/WSS connections.</p>
        <hr>
        <p><small>This server is running with TLS encryption enabled.</small></p>
    </div>
</body>
</html>`))
				return
			}
		}

		// Stealth mode for all other paths
		if hijacker, ok := w.(http.Hijacker); ok {
			conn, _, err := hijacker.Hijack()
			if err == nil {
				conn.Close()
			}
		}
	})

	// Determine if we should use TLS
	useTLS = false
	if enableTLS == "true" || enableTLS == "1" || enableTLS == "yes" {
		useTLS = true
	}

	// Auto-detect TLS if cert files are provided
	if certFile != "" && keyFile != "" {
		if _, err := os.Stat(certFile); err == nil {
			if _, err := os.Stat(keyFile); err == nil {
				useTLS = true
			}
		}
	}

	// Default cert/key files if not specified
	if useTLS && (certFile == "" || keyFile == "") {
		certFile = "server.crt"
		keyFile = "server.key"

		// Check if default files exist
		if _, err := os.Stat(certFile); err != nil {
			useTLS = false
			log.Printf("Warning: TLS requested but cert file '%s' not found", certFile)
		}
		if _, err := os.Stat(keyFile); err != nil {
			useTLS = false
			log.Printf("Warning: TLS requested but key file '%s' not found", keyFile)
		}
	}

	log.Printf("Ming-Mong WebSocket server starting on port %s", port)

	if useTLS {
		log.Printf("TLS enabled - using cert: %s, key: %s", certFile, keyFile)
		log.Printf("WebSocket endpoint: wss://localhost:%s/ws", port)
		log.Printf("Security: Encrypted WebSocket connections (WSS)")

		if err := http.ListenAndServeTLS(":"+port, certFile, keyFile, nil); err != nil {
			log.Fatalf("HTTPS server failed to start: %v", err)
		}
	} else {
		log.Printf("TLS disabled - using plain HTTP")
		log.Printf("WebSocket endpoint: ws://localhost:%s/ws", port)
		log.Printf("Security: Plain WebSocket connections (WS)")
		log.Printf("Note: For production use, enable TLS with ENABLE_TLS=true")

		if err := http.ListenAndServe(":"+port, nil); err != nil {
			log.Fatalf("HTTP server failed to start: %v", err)
		}
	}
}
