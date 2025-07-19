# 🚀 Ming-Mong WebSocket Server

A minimal WebSocket server with **stealth mode** and **signature-based authentication** (no secret keys required).

## 🔒 Security Features

- **No secret keys** - Authentication uses SHA256 hash of date + server name
- **Stealth mode** - Unknown endpoints cause immediate connection drops (server appears offline)
- **Signature validation** - Only valid signatures get responses
- **CORS-free** - WebSocket bypasses browser CORS restrictions
- **Timezone tolerance** - Accepts signatures for current and previous day

## 🏗️ Quick Install

```bash
# Basic installation (WS)
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash

# With custom port
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- -p 9090

# With automatic Let's Encrypt certificate (RECOMMENDED)
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- --auto-ssl

# With self-signed certificates
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- --tls

# With custom port and auto SSL
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- -p 443 --auto-ssl
```

## 📋 WebSocket Protocol

### Endpoint

**Plain WebSocket (WS):**
```
ws://your-server-ip:8080/ws
```

**Secure WebSocket (WSS):**
```
wss://your-server-ip:8080/ws
```

**Note:** Replace `your-server-ip` with your actual server IP address (e.g., `192.168.1.100` or `localhost` for local testing)

### Request Format
```json
{
  "type": "ping",
  "signature": "a1b2c3d4e5f6g7h8",
  "timestamp": "2024-01-15T10:30:45Z"
}
```

### Response Format

**Success:**
```json
{
  "type": "pong",
  "status": "ok",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "server_time": "2024-01-15T10:30:45.123Z"
}
```

**Error:**
```json
{
  "type": "error",
  "error": "invalid_signature",
  "timestamp": "2024-01-15T10:30:45.123Z"
}
```

## 🔐 Signature Algorithm

The signature is generated using this algorithm:
```
SHA256(date + "ming-mong-server")[:16]
```

Where:
- `date` is in UTC format: `YYYY-MM-DD` (e.g., "2024-01-15")
- Result is truncated to first 16 characters

## 💻 Client Examples

### JavaScript (Browser)
```javascript
function generateSignature() {
    const date = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const data = date + 'ming-mong-server';

    // Using Web Crypto API
    const encoder = new TextEncoder();
    return crypto.subtle.digest('SHA-256', encoder.encode(data))
        .then(hashBuffer => {
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
            return hashHex.slice(0, 16);
        });
}

async function pingServer(useSSL = false) {
    // Check WebSocket support
    if (!window.WebSocket) {
        console.error('WebSocket not supported by this browser');
        return;
    }

    const signature = await generateSignature();
    const protocol = useSSL ? 'wss' : 'ws';
    const ws = new WebSocket(`${protocol}://your-server-ip:8080/ws`);

    ws.onopen = () => {
        console.log(`WebSocket connected (${protocol.toUpperCase()})`);
        ws.send(JSON.stringify({
            type: 'ping',
            signature: signature,
            timestamp: new Date().toISOString()
        }));
    };

    ws.onmessage = (event) => {
        const response = JSON.parse(event.data);
        console.log('Server response:', response);

        if (response.type === 'pong') {
            console.log('✅ Ping successful!');
        } else if (response.type === 'error') {
            console.error('❌ Server error:', response.error);
        }

        ws.close();
    };

    ws.onclose = (event) => {
        console.log('WebSocket closed:', event.code, event.reason);
    };

    ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        if (useSSL) {
            console.error('TLS/SSL connection failed. Check certificate or use HTTP page for WSS.');
        }
    };
}

// Usage examples:
pingServer(false); // Plain WebSocket (WS)
pingServer(true);  // Secure WebSocket (WSS)
```

### Node.js
```javascript
const WebSocket = require('ws');
const crypto = require('crypto');

function generateSignature() {
    const date = new Date().toISOString().split('T')[0];
    const data = date + 'ming-mong-server';
    return crypto.createHash('sha256').update(data).digest('hex').slice(0, 16);
}

function pingServer() {
    const ws = new WebSocket('ws://your-server-ip:8080/ws');

    ws.on('open', () => {
        console.log('WebSocket connected');
        ws.send(JSON.stringify({
            type: 'ping',
            signature: generateSignature(),
            timestamp: new Date().toISOString()
        }));
    });

    ws.on('message', (data) => {
        const response = JSON.parse(data);
        console.log('Server response:', response);

        if (response.type === 'pong') {
            console.log('✅ Ping successful!');
        } else if (response.type === 'error') {
            console.error('❌ Server error:', response.error);
        }

        ws.close();
    });

    ws.on('close', (code, reason) => {
        console.log('WebSocket closed:', code, reason.toString());
    });

    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
    });
}

pingServer();
```

### Python
```python
import asyncio
import websockets
import json
import hashlib
from datetime import datetime

def generate_signature():
    date = datetime.utcnow().strftime('%Y-%m-%d')
    data = date + 'ming-mong-server'
    return hashlib.sha256(data.encode()).hexdigest()[:16]

async def ping_server():
    uri = "ws://your-server-ip:8080/ws"

    async with websockets.connect(uri) as websocket:
        message = {
            "type": "ping",
            "signature": generate_signature(),
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }

        await websocket.send(json.dumps(message))
        response = await websocket.recv()

        print("Server response:", json.loads(response))

asyncio.run(ping_server())
```

### Go
```go
package main

import (
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log"
    "time"

    "github.com/gorilla/websocket"
)

type PingMessage struct {
    Type      string `json:"type"`
    Signature string `json:"signature"`
    Timestamp string `json:"timestamp"`
}

func generateSignature() string {
    date := time.Now().UTC().Format("2006-01-02")
    data := date + "ming-mong-server"
    hash := sha256.Sum256([]byte(data))
    return hex.EncodeToString(hash[:])[:16]
}

func main() {
    conn, _, err := websocket.DefaultDialer.Dial("ws://your-server-ip:8080/ws", nil)
    if err != nil {
        log.Fatal("dial:", err)
    }
    defer conn.Close()

    message := PingMessage{
        Type:      "ping",
        Signature: generateSignature(),
        Timestamp: time.Now().UTC().Format(time.RFC3339),
    }

    err = conn.WriteJSON(message)
    if err != nil {
        log.Fatal("write:", err)
    }

    var response map[string]interface{}
    err = conn.ReadJSON(&response)
    if err != nil {
        log.Fatal("read:", err)
    }

    fmt.Printf("Server response: %+v\n", response)
}
```

### PHP
```php
<?php
require_once 'vendor/autoload.php';

use Ratchet\Client\WebSocket;
use Ratchet\Client\Connector;

function generateSignature() {
    $date = gmdate('Y-m-d');
    $data = $date . 'ming-mong-server';
    return substr(hash('sha256', $data), 0, 16);
}

$connector = new Connector();
$connector('ws://your-server-ip:8080/ws')
    ->then(function (WebSocket $conn) {
        $message = json_encode([
            'type' => 'ping',
            'signature' => generateSignature(),
            'timestamp' => gmdate('c')
        ]);

        $conn->send($message);

        $conn->on('message', function ($msg) {
            echo "Server response: " . $msg . "\n";
        });
    });
?>
```

### Bash (with wscat)
```bash
#!/bin/bash

# Install wscat if not available
# npm install -g wscat

# Generate signature
DATE=$(date -u +"%Y-%m-%d")
# Linux
SIGNATURE=$(echo -n "${DATE}ming-mong-server" | sha256sum | cut -c1-16)
# macOS (uncomment if needed)
# SIGNATURE=$(echo -n "${DATE}ming-mong-server" | shasum -a 256 | cut -c1-16)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create message
MESSAGE=$(cat <<EOF
{
  "type": "ping",
  "signature": "$SIGNATURE",
  "timestamp": "$TIMESTAMP"
}
EOF
)

# Send via wscat
echo "$MESSAGE" | wscat -c ws://your-server-ip:8080/ws
```

## 🚀 Testing

### Using wscat
```bash
# Install wscat
npm install -g wscat

# Connect to plain WebSocket
wscat -c ws://your-server-ip:8080/ws

# Connect to secure WebSocket
wscat -c wss://your-server-ip:8080/ws

# For self-signed certificates (ignore SSL errors)
wscat -c wss://your-server-ip:8080/ws --no-check

# Then send (replace with actual signature):
{"type":"ping","signature":"a1b2c3d4e5f6g7h8","timestamp":"2024-01-15T10:30:45Z"}
```

### Generate Today's Signature
```bash
DATE=$(date -u +"%Y-%m-%d")
# Linux
SIGNATURE=$(echo -n "${DATE}ming-mong-server" | sha256sum | cut -c1-16)
# macOS
# SIGNATURE=$(echo -n "${DATE}ming-mong-server" | shasum -a 256 | cut -c1-16)
echo "Today's signature: $SIGNATURE"
```

## 🔧 Configuration

### Environment Variables
- `PORT` - Server port (default: 8080)
- `ENABLE_TLS` - Enable TLS/SSL (true/false, default: false)
- `TLS_CERT_FILE` - Path to TLS certificate file (default: server.crt)
- `TLS_KEY_FILE` - Path to TLS private key file (default: server.key)

## 🌐 Solutions for Servers without Domain Names

### **Option 1: Automatic SSL with nip.io (RECOMMENDED)**

**One-line installation:**
```bash
# Automatic installation with Let's Encrypt
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- --auto-ssl
```

**Requirements:**
- ⚠️ **Requires sudo privileges** for certbot and certificate management
- 🌐 **Port 80 must be accessible** from the internet for Let's Encrypt validation
- 🔒 **Port 443 recommended** for HTTPS (or use custom port)
- 🛠️ **marzban-node support**: Automatically stops/starts marzban-node if detected

**What it does:**
1. 🔍 Detects your server's external IP address
2. 🌐 Creates domain: `YOUR_IP.nip.io` (automatically resolves to your IP)
3. 🛠️ Safely stops marzban-node (if running) to free port 80
4. 🔐 Gets valid Let's Encrypt SSL certificate
5. 🔄 Restarts marzban-node (if it was stopped)
6. 🚀 Starts server with trusted certificate

**Result:**
```bash
# Your server IP: 192.168.1.100
# Domain: 192.168.1.100.nip.io
# URLs:
#   - https://192.168.1.100.nip.io/pixel (iron-clad method)
#   - https://192.168.1.100.nip.io/jsonp (iron-clad method)
#   - wss://192.168.1.100.nip.io/ws
```

**Usage from HTTPS pages:**
```javascript
// Iron-clad method - works immediately, no certificate warnings!
const img = new Image();
img.onload = () => console.log('Server OK');
img.src = 'https://192.168.1.100.nip.io/pixel?signature=your_signature';

const ws = new WebSocket('wss://192.168.1.100.nip.io/ws');
```

### **Option 2: Manual nip.io setup**

```bash
# Your server IP: 192.168.1.100
# Use domain: 192.168.1.100.nip.io (automatically resolves to IP)

# Get valid SSL certificate
certbot certonly --standalone -d 192.168.1.100.nip.io

# Run with valid certificate
docker run -d -p 443:443 \
  -e PORT=443 \
  -e ENABLE_TLS=true \
  -e TLS_CERT_FILE=/etc/letsencrypt/live/192.168.1.100.nip.io/fullchain.pem \
  -e TLS_KEY_FILE=/etc/letsencrypt/live/192.168.1.100.nip.io/privkey.pem \
  -v /etc/letsencrypt:/etc/letsencrypt \
  ming-mong
```

### **Option 2: Iron-Clad Communication (CORS/SSL-Free)**

**🛡️ Maximum Reliability Methods (Works Everywhere):**

```javascript
// Method 1: Pixel Tracking (★★★★★ Reliability)
function pingServer(signature) {
    const img = new Image();
    img.onload = () => console.log('✅ Server responded');
    img.onerror = () => console.log('❌ Server failed');
    img.src = `http://82.148.17.45:8080/pixel?signature=${signature}&timestamp=${Date.now()}`;
}

// Method 2: JSONP (★★★★☆ Reliability)
function pingServerJSONP(signature) {
    window.callback = (data) => console.log('Response:', data);
    const script = document.createElement('script');
    script.src = `http://82.148.17.45:8080/jsonp?signature=${signature}&callback=callback`;
    document.head.appendChild(script);
}
```

**🧪 Test Methods:**
Use the JavaScript examples above directly in your browser console.

**Why These Methods Work:**
- 🖼️ **Pixel Tracking**: Uses `<img>` tag - no CORS restrictions
- 📞 **JSONP**: Uses `<script>` tag - bypasses all security policies  
- 🌐 **Works from HTTPS pages**: No Mixed Content Security issues
- 🔄 **Works everywhere**: All browsers, all configurations

### **Option 3: Mixed Mode (HTTP + HTTPS)**

Use both HTTP and HTTPS endpoints:

```bash
# Install with TLS for WSS support
./install.sh --tls

# Server will support both:
# - http://192.168.1.100:8080/pixel (HTTP iron-clad)
# - http://192.168.1.100:8080/jsonp (HTTP iron-clad)
# - https://192.168.1.100:8080/pixel (HTTPS iron-clad)
# - https://192.168.1.100:8080/jsonp (HTTPS iron-clad)
# - ws://192.168.1.100:8080/ws (WebSocket)
# - wss://192.168.1.100:8080/ws (Secure WebSocket)
```

**Usage:**
```javascript
// Iron-clad methods for any page (HTTP/HTTPS)
function pingServer(serverIP, signature) {
    // Method 1: Pixel tracking (most reliable)
    const img = new Image();
    img.onload = () => console.log('✅ Server OK');
    img.onerror = () => console.log('❌ Server failed');
    img.src = `http://${serverIP}:8080/pixel?signature=${signature}`;
    
    // Method 2: JSONP (with response data)
    window.callback = (data) => console.log('Server response:', data);
    const script = document.createElement('script');
    script.src = `http://${serverIP}:8080/jsonp?signature=${signature}&callback=callback`;
    document.head.appendChild(script);
}
```

### Docker Examples

**Plain WebSocket (WS):**
```bash
docker run -d -p 8080:8080 -e PORT=8080 ming-mong
```

**Secure WebSocket (WSS) with custom certificates:**
```bash
docker run -d -p 8080:8080 \
  -e PORT=8080 \
  -e ENABLE_TLS=true \
  -e TLS_CERT_FILE=/app/certs/server.crt \
  -e TLS_KEY_FILE=/app/certs/server.key \
  -v /path/to/certs:/app/certs \
  ming-mong
```

**Generate self-signed certificates:**
```bash
# Create certificate directory
mkdir -p certs

# Generate private key
openssl genrsa -out certs/server.key 2048

# Generate certificate
openssl req -new -x509 -key certs/server.key -out certs/server.crt -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Run with TLS
docker run -d -p 8080:8080 \
  -e PORT=8080 \
  -e ENABLE_TLS=true \
  -v $(pwd)/certs:/app/certs \
  ming-mong
```

## 🛡️ Security Levels

| Level | Protocol | Features |
|-------|----------|----------|
| **Basic** | WS | WebSocket with signature validation |
| **Secure** | WSS | Encrypted WebSocket with TLS/SSL |
| **Stealth** | WS/WSS | Unknown endpoints cause connection drops |
| **Paranoid** | WSS | Encrypted + No signature generation endpoint |

### Security Comparison

| Feature | WS | WSS |
|---------|----|----|
| **Encryption** | ❌ Plain text | ✅ TLS encrypted |
| **Certificate** | ❌ Not required | ✅ Required |
| **Mixed Content** | ⚠️ Limited on HTTPS | ✅ Works everywhere |
| **Production Ready** | ⚠️ Internal only | ✅ Internet-facing |
| **Performance** | ✅ Faster | ⚠️ Slight overhead |

## 📝 Error Codes

| Error | Description |
|-------|-------------|
| `invalid_format` | Invalid JSON message format |
| `invalid_type` | Message type is not "ping" |
| `invalid_signature` | Signature validation failed |

## 🔄 Behavior

- **Valid signature**: Returns `pong` response, closes connection
- **Invalid signature**: Returns `error` response, closes connection
- **Unknown endpoint**: Immediate connection drop (stealth mode)
- **Timeout**: 5 seconds read timeout

## 📚 Manual Installation

```bash
# Clone repository
git clone https://github.com/suzzukin/ming-mong.git
cd ming-mong

# Build and run
go mod tidy
go build -o ming-mong
./ming-mong

# Or with Docker
docker build -t ming-mong .
docker run -d -p 8080:8080 ming-mong
```

## 🔧 Troubleshooting

### Connection Issues
- Check firewall settings
- Verify WebSocket URL format: `ws://` not `http://`
- Ensure server is running on correct port

### Signature Issues
- Verify date format is `YYYY-MM-DD` in UTC
- Check signature algorithm implementation
- Remember: signature is first 16 chars of SHA256 hash

### WebSocket Issues
- Modern browsers support WebSockets natively
- Use `ws://` for plain connections
- Use `wss://` for secure connections (requires SSL/TLS)
- Check browser console for detailed error messages
- WebSocket errors are often network-related (firewall, proxy, etc.)

### TLS/SSL Issues
- **Self-signed certificates**: Browsers will show security warnings
- **Certificate validation**: Use `--no-check` flag with wscat for self-signed certs
- **Mixed content**: HTTPS pages can only connect to `wss://` endpoints
- **Certificate errors**: Ensure certificate matches the domain/IP you're connecting to
- **Production use**: Consider using Let's Encrypt or proper CA-issued certificates

### Browser WSS Setup (Self-signed certificates)

**Step 1: Install server with TLS**
```bash
# Install with TLS enabled
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- --tls
```

**Step 2: Accept certificate in browser**
1. Open `https://localhost:8080` in your browser
2. You'll see a security warning like "Your connection is not private"
3. Click "Advanced" → "Proceed to localhost (unsafe)"
4. You should see "Certificate Accepted Successfully!" page
5. Now WSS connections will work from JavaScript

**Step 3: Test WebSocket connection**
```javascript
// This will work after accepting the certificate
const ws = new WebSocket('wss://localhost:8080/ws');
```

**Step 4: Use test page**
Download and open [test-wss.html](test-wss.html) in your browser for interactive testing with diagnostics.

**Step 5: Run diagnostics (if issues)**
```bash
# Download and run diagnostic script
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/diagnose.sh | bash
```

### Common Issues and Solutions

**Problem: "Could not connect to the server"**
- ✅ **Check if server is running**: `docker ps` or `lsof -i :8080`
- ✅ **Try WS first**: Use `ws://localhost:8080/ws` to test basic connectivity
- ✅ **Check port**: Make sure port 8080 is not blocked by firewall

**Problem: "SSL error has occurred"**
- ✅ **Server not running with TLS**: Make sure you used `--tls` flag during installation
- ✅ **Certificate not accepted**: Open `https://localhost:8080` and accept the warning
- ✅ **Wrong protocol**: Use `wss://` for TLS-enabled servers

**Problem: "WebSocket connection failed"**
- ✅ **Mixed content**: If testing from HTTPS page, you must use WSS
- ✅ **Certificate issues**: Clear browser cache and re-accept certificate
- ✅ **Firewall**: Check if port 8080 is allowed through firewall

**Alternative: Use Chrome with disabled security (testing only)**
```bash
# Launch Chrome with disabled SSL verification (NOT for production!)
google-chrome --ignore-certificate-errors --ignore-ssl-errors --allow-running-insecure-content
```

**Production solution: Use valid certificates**
```bash
# With Let's Encrypt (for real domains)
certbot certonly --standalone -d yourdomain.com

# Then use the certificates
docker run -d -p 443:443 \
  -e PORT=443 \
  -e ENABLE_TLS=true \
  -v /etc/letsencrypt/live/yourdomain.com:/app/certs \
  ming-mong
```

## 🗑️ Uninstall

```bash
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/uninstall.sh | bash
```

---

**Note**: This server is designed for internal networks. For internet-facing deployments, consider using HTTPS/WSS with proper SSL certificates.