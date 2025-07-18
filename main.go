package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

// generateSignature creates a signature based on date without secret key
func generateSignature(date string) string {
	// Simple algorithm: date + application name
	data := date + "ming-mong-server"

	// SHA256 hash
	hash := sha256.Sum256([]byte(data))

	// Take only first 16 characters for simplicity
	return hex.EncodeToString(hash[:])[:16]
}

// getCurrentSignature returns signature for current date
func getCurrentSignature() string {
	currentDate := time.Now().UTC().Format("2006-01-02") // Format YYYY-MM-DD
	return generateSignature(currentDate)
}

// getPreviousSignature returns signature for previous day
func getPreviousSignature() string {
	previousDate := time.Now().UTC().AddDate(0, 0, -1).Format("2006-01-02")
	return generateSignature(previousDate)
}

// isValidSignature checks signature validity (current or previous day)
func isValidSignature(signature string) bool {
	// Check current day
	if signature == getCurrentSignature() {
		return true
	}

	// Check previous day (for timezone differences)
	if signature == getPreviousSignature() {
		log.Printf("Valid signature for previous day used")
		return true
	}

	return false
}

// closeConnection closes the connection without any response
func closeConnection(w http.ResponseWriter, r *http.Request, reason string) {
	log.Printf("Closing connection from %s: %s", r.RemoteAddr, reason)

	// Cast to http.Hijacker to take control of the connection
	if hijacker, ok := w.(http.Hijacker); ok {
		conn, _, err := hijacker.Hijack()
		if err != nil {
			log.Printf("Failed to hijack connection: %v", err)
			return
		}
		// Close connection immediately without any response
		conn.Close()
	} else {
		// Fallback: just return without writing anything
		return
	}
}

// handlePing handles requests to /ping
func handlePing(w http.ResponseWriter, r *http.Request) {
	// Handle CORS preflight request
	if r.Method == http.MethodOptions {
		log.Printf("CORS preflight request from %s", r.RemoteAddr)
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "X-Ping-Signature")
		w.Header().Set("Access-Control-Max-Age", "86400") // 24 hours
		w.WriteHeader(http.StatusNoContent)
		return
	}

	// Check request method
	if r.Method != http.MethodGet {
		closeConnection(w, r, "invalid method: "+r.Method)
		return
	}

	// Get signature from header
	providedSignature := r.Header.Get("X-Ping-Signature")
	if providedSignature == "" {
		closeConnection(w, r, "missing signature")
		return
	}

	// Check signature validity
	if !isValidSignature(providedSignature) {
		closeConnection(w, r, "invalid signature: "+providedSignature)
		return
	}

	log.Printf("Valid ping request from %s", r.RemoteAddr)

	// Set CORS headers for browser requests
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET")
	w.Header().Set("Content-Type", "application/json")

	// Create response
	response := map[string]string{"status": "ok"}
	json.NewEncoder(w).Encode(response)
}

// handleDefault handles all other requests by closing connection
func handleDefault(w http.ResponseWriter, r *http.Request) {
	closeConnection(w, r, "unknown endpoint: "+r.URL.Path)
}

// getPort returns the port to listen on, from environment variable or default
func getPort() string {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	return port
}

func main() {
	port := getPort()

	// Register handlers (order matters: most specific first)
	http.HandleFunc("/ping", handlePing)
	http.HandleFunc("/", handleDefault) // Handle all other paths

	// Print startup information
	log.Printf("Starting Ming-Mong server on port %s", port)
	log.Printf("Today's signature: %s", getCurrentSignature())
	log.Println("Algorithm: SHA256(date + 'ming-mong-server')[:16]")
	log.Println("Security: Invalid requests cause connection drop (no response)")
	log.Println("Security: Unknown endpoints also cause connection drop")
	log.Println("Security: No signature endpoint - clients must generate signatures locally")
	log.Println("CORS: OPTIONS requests are handled for browser compatibility")
	log.Println("Endpoints:")
	log.Println("  GET /ping - Health check (requires X-Ping-Signature header)")
	log.Println("  OPTIONS /ping - CORS preflight (no signature required)")
	log.Println("  * (all other paths) - Connection closed immediately")

	// Start server on specified port
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
