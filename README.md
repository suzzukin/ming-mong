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
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash
```

Or with custom port:
```bash
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/install.sh | bash -s -- -p 9090
```

## 📋 WebSocket Protocol

### Endpoint
```
ws://your-server-ip:8080/ws
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

async function pingServer() {
    // Check WebSocket support
    if (!window.WebSocket) {
        console.error('WebSocket not supported by this browser');
        return;
    }
    
    const signature = await generateSignature();
    const ws = new WebSocket('ws://your-server-ip:8080/ws');
    
    ws.onopen = () => {
        console.log('WebSocket connected');
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
    };
}

pingServer();
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

# Connect and send message
wscat -c ws://your-server-ip:8080/ws

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

### Docker
```bash
docker run -d -p 8080:8080 -e PORT=8080 ming-mong
```

## 🛡️ Security Levels

| Level | Features |
|-------|----------|
| **Basic** | WebSocket with signature validation |
| **Stealth** | Unknown endpoints cause connection drops |
| **Paranoid** | No signature generation endpoint |

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

## 🗑️ Uninstall

```bash
curl -sSL https://raw.githubusercontent.com/suzzukin/ming-mong/master/uninstall.sh | bash
```

---

**Note**: This server is designed for internal networks. For internet-facing deployments, consider using HTTPS/WSS with proper SSL certificates.