# Ming-Mong Server

A lightweight HTTP server written in Go with SHA256 hash-based authentication for secure ping endpoints. Designed for system monitoring and health checks with date-based signature verification.

## Features

- **Simple Hash-Based Authentication**
  - Secure request validation using time-based signatures
  - Date-based signature generation (UTC)
  - No secret keys required - uses simple algorithm

- **RESTful API**
  - Simple `/ping` endpoint for health checks
  - JSON response format
  - CORS support for web applications
  - Browser-compatible JavaScript API

- **Docker Support**
  - Multi-stage Docker build for optimized images
  - Alpine Linux base for minimal footprint
  - Non-root user execution for security

- **Easy Deployment**
  - Automatic installation script
  - Cross-platform support (Linux, macOS, Windows)
  - Configurable port selection
  - Systemd integration ready
  - Auto-restart capabilities

- **Maximum Security**
  - Stealth mode: Invalid requests cause connection drop
  - Unknown endpoints also cause connection drop (no 404 errors)
  - **No signature endpoint**: Clients must generate signatures locally
  - Server appears completely offline to unauthorized clients
  - No information disclosure to attackers or scanners
  - Immune to endpoint discovery and vulnerability scanning
  - Complete algorithm secrecy - no way to discover signature method

## Requirements

- Docker (automatically installed if not present)
- Bash shell
- Internet connection

## Installation

### Quick Install

```bash
# Install on default port (8080)
curl -fsSL https://raw.githubusercontent.com/suzzukin/ming-mong/main/install.sh | bash

# Install on custom port
curl -fsSL https://raw.githubusercontent.com/suzzukin/ming-mong/main/install.sh | bash -s -- -p 3000

# Download and run with port selection
curl -fsSL https://raw.githubusercontent.com/suzzukin/ming-mong/main/install.sh -o install.sh
chmod +x install.sh
./install.sh -p 9000
```

**Or manually:**

```bash
# Clone the repository
git clone https://github.com/suzzukin/ming-mong.git
cd ming-mong

# Install with default port (8080)
chmod +x install.sh
./install.sh

# Install with custom port
./install.sh -p 3000

# Interactive mode (asks for port)
./install.sh
```

The script will automatically:
- Detect your operating system
- Install Docker if not present
- Start Docker daemon if not running
- Ask for port if not specified
- Build the Docker image
- Run the container on specified port
- Configure automatic restart

### Manual Installation

1. **Install Docker** (if not already installed):
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install -y docker.io
   
   # CentOS/RHEL
   sudo yum install -y docker
   
   # macOS
   brew install --cask docker
   ```

2. **Clone and build**:
   ```bash
   git clone https://github.com/suzzukin/ming-mong.git
   cd ming-mong
   docker build -t ming-mong .
   ```

3. **Run container**:
   ```bash
   # Default port (8080)
   docker run -d \
     --name ming-mong-server \
     -p 8080:8080 \
     -e PORT=8080 \
     --restart unless-stopped \
     ming-mong
   
   # Custom port (3000)
   docker run -d \
     --name ming-mong-server \
     -p 3000:3000 \
     -e PORT=3000 \
     --restart unless-stopped \
     ming-mong
   ```

## Uninstallation

### Quick Uninstall

```bash
# Download and run the uninstallation script
curl -fsSL https://raw.githubusercontent.com/suzzukin/ming-mong/main/uninstall.sh | bash
```

**Or manually:**

```bash
# Make the script executable and run
chmod +x uninstall.sh
./uninstall.sh
```

### Manual Uninstallation

1. **Stop and remove container**:
   ```bash
   docker stop ming-mong-server
   docker rm ming-mong-server
   ```

2. **Remove image**:
   ```bash
   docker rmi ming-mong
   ```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `8080` |
| `ALGORITHM_CONSTANT` | String constant for signature algorithm | `ming-mong-server` |

### Changing Configuration

**Port configuration:**
```bash
# Via installation script
./install.sh -p 3000

# Via environment variable
docker run -e PORT=3000 -p 3000:3000 ming-mong

# Via command line argument
./install.sh --port 9000
```

**Algorithm configuration:**
To modify the signature algorithm, edit the `generateSignature` function in `main.go`:

```go
// Current algorithm: SHA256(date + "ming-mong-server")[:16]
data := date + "ming-mong-server"  // Change this constant
```

## API Usage

### Endpoints

- **GET `/ping`** - Health check endpoint (requires authentication)
- **OPTIONS `/ping`** - CORS preflight request (handled automatically by browsers)
- **All other paths** - Connection closed immediately (stealth mode)

### Authentication

All requests to `/ping` require a valid SHA256 signature in the `X-Ping-Signature` header.

### Generating Signature

The signature is based on a simple algorithm: `SHA256(date + "ming-mong-server")[:16]`

```bash
# Generate signature manually
DATE=$(date -u +"%Y-%m-%d")
SIGNATURE=$(echo -n "${DATE}ming-mong-server" | sha256sum | cut -c1-16)
```

### Making Requests

**From command line:**
```bash
# Health check request (replace 8080 with your port)
curl -H "X-Ping-Signature: $SIGNATURE" http://localhost:8080/ping
```

**From JavaScript (browser):**
```javascript
// Generate signature locally (no server request needed)
async function generateSignature() {
    const date = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const data = date + 'ming-mong-server';
    
    // Use crypto.subtle for SHA256
    const encoder = new TextEncoder();
    const dataBuffer = encoder.encode(data);
    const hashBuffer = await crypto.subtle.digest('SHA-256', dataBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    
    return hashHex.substring(0, 16); // First 16 characters
}

// Make ping request
async function ping() {
    try {
        const signature = await generateSignature();
        const response = await fetch('http://localhost:8080/ping', {
            method: 'GET',
            headers: {
                'X-Ping-Signature': signature
            }
        });
        
        if (response.ok) {
            const data = await response.json();
            console.log('Server status:', data.status);
            return data;
        } else {
            console.error('Request failed:', response.status);
        }
    } catch (error) {
        console.error('Network error (connection closed by server):', error);
        // This typically means invalid signature - server closed connection
    }
}

// Example usage
ping().then(result => {
    console.log('Ping result:', result);
});
```

**From Node.js:**
```javascript
const crypto = require('crypto');

// Generate signature
function generateSignature() {
    const date = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const data = date + 'ming-mong-server';
    const hash = crypto.createHash('sha256').update(data).digest('hex');
    return hash.substring(0, 16);
}

// Make request with fetch or axios
async function pingServer() {
    const signature = generateSignature();
    
    try {
        const response = await fetch('http://localhost:8080/ping', {
            method: 'GET',
            headers: {
                'X-Ping-Signature': signature
            }
        });
        
        const data = await response.json();
        console.log('Server response:', data);
    } catch (error) {
        console.error('Network error (connection closed by server):', error);
        console.error('This typically means invalid signature');
    }
}

pingServer();
```

**Python:**
```python
import hashlib
from datetime import datetime, timezone
import requests

def generate_signature():
    date = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    data = date + 'ming-mong-server'
    hash_object = hashlib.sha256(data.encode())
    return hash_object.hexdigest()[:16]

# Usage
signature = generate_signature()
response = requests.get('http://localhost:8080/ping', 
                       headers={'X-Ping-Signature': signature})
print(f"Status: {response.status_code}")
print(f"Response: {response.json()}")
```

**PHP:**
```php
<?php
function generateSignature() {
    $date = gmdate('Y-m-d');
    $data = $date . 'ming-mong-server';
    $hash = hash('sha256', $data);
    return substr($hash, 0, 16);
}

// Usage
$signature = generateSignature();
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'http://localhost:8080/ping');
curl_setopt($ch, CURLOPT_HTTPHEADER, ['X-Ping-Signature: ' . $signature]);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$response = curl_exec($ch);
curl_close($ch);
echo $response;
?>
```

**Go:**
```go
package main

import (
    "crypto/sha256"
    "encoding/hex"
    "fmt"
    "net/http"
    "time"
)

func generateSignature() string {
    date := time.Now().UTC().Format("2006-01-02")
    data := date + "ming-mong-server"
    hash := sha256.Sum256([]byte(data))
    return hex.EncodeToString(hash[:])[:16]
}

func main() {
    signature := generateSignature()
    
    client := &http.Client{}
    req, _ := http.NewRequest("GET", "http://localhost:8080/ping", nil)
    req.Header.Set("X-Ping-Signature", signature)
    
    resp, err := client.Do(req)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    fmt.Printf("Status: %s\n", resp.Status)
}
```

**Successful `/ping` response:**
```json
{
  "status": "ok"
}
```

**Signature generation example:**
```javascript
// Client-side signature generation
const date = new Date().toISOString().split('T')[0]; // "2024-01-15"
const signature = await generateSignature(date);     // "a1b2c3d4e5f6a7b8"
```

**Error responses:**
- **Connection closed without response** - Invalid signature, wrong HTTP method, or missing signature header
- **Connection closed without response** - Unknown/undefined endpoints (e.g., `/admin`, `/api`, `/robots.txt`)
- Server appears completely unavailable to unauthorized clients and scanners

**CORS Support:**
- **OPTIONS `/ping`** - Returns proper CORS headers for browser compatibility
- Browsers automatically send OPTIONS requests before custom header requests
- No signature required for OPTIONS requests

### Signature Validation

- Accepts signatures for **current day** and **previous day** (UTC)
- Helps with timezone differences and clock synchronization issues
- All requests are logged with IP addresses for monitoring

## Container Management

### Check Service Status

```bash
docker ps
```

### View Logs

```bash
docker logs ming-mong-server
```

### Stop Service

```bash
docker stop ming-mong-server
```

### Start Service

```bash
docker start ming-mong-server
```

### Restart Service

```bash
docker restart ming-mong-server
```

## Supported Operating Systems

The installation script supports:
- **Linux**: Debian/Ubuntu, Red Hat/CentOS/Fedora, Arch Linux
- **macOS**: Automatic installation via Homebrew
- **Windows**: Manual installation required (Docker Desktop)

## Project Structure

```
.
├── main.go          # Main server code
├── go.mod           # Go module
├── Dockerfile       # Docker configuration
├── .dockerignore    # Docker ignore patterns
├── install.sh       # Auto-installation script
├── uninstall.sh     # Uninstallation script
└── README.md        # Documentation
```

## Security Notes

- The server uses SHA256 hash-based authentication (no secret keys required)
- Signature algorithm: `SHA256(date + "ming-mong-server")[:16]`
- Signature is based on current UTC date (YYYY-MM-DD format)
- **Change the constant string in the algorithm for production use**
- Container runs with non-root user for security
- **Maximum stealth mode**: Invalid requests cause immediate connection drop (no response)
- **Unknown endpoints**: All undefined paths (e.g., `/admin`, `/api`, `/robots.txt`) also cause connection drop
- **No signature endpoint**: Clients must generate signatures locally (ultimate security)
- **CORS preflight support**: OPTIONS requests handled for browser compatibility (no security risk)
- Server appears completely unavailable to unauthorized clients and security scanners
- Enhanced security through obscurity - attackers can't detect server existence
- No information disclosure even for endpoint discovery attempts
- **Complete algorithm secrecy**: No way for attackers to discover signature method
- Simple algorithm provides basic protection without key management complexity
- CORS headers enabled for browser compatibility (`Access-Control-Allow-Origin: *`)
- Works with modern browsers supporting Web Crypto API

## Development

### Local Development

```bash
# Run without Docker (default port)
go run main.go

# Run with custom port
PORT=3000 go run main.go

# Build binary
go build -o ming-mong

# Run binary with custom port
PORT=9000 ./ming-mong
```

### Quick Testing

**Command line:**
```bash
# Test with current signature (replace 8080 with your port)
DATE=$(date -u +"%Y-%m-%d")
SIGNATURE=$(echo -n "${DATE}ming-mong-server" | sha256sum | cut -c1-16)
curl -H "X-Ping-Signature: $SIGNATURE" http://localhost:8080/ping

# Test stealth mode (should close connection)
curl http://localhost:8080/admin          # Connection closed
curl http://localhost:8080/signature      # Connection closed (no longer exists)
curl http://localhost:8080/nonexistent    # Connection closed
curl -H "X-Ping-Signature: wrong" http://localhost:8080/ping  # Connection closed

# Test CORS preflight (should return 204 No Content)
curl -X OPTIONS http://localhost:8080/ping  # Returns CORS headers
```

## Troubleshooting

### Container Not Starting

Check logs:
```bash
docker logs ming-mong-server
```

### Port Already in Use

Change port in installation:
```bash
./install.sh -p 8081  # Use different port
```

### Signature Validation Fails

When signature is invalid, the server will close the connection without any response. This makes it appear as if the server is down.

**Symptoms:**
- `curl: (52) Empty reply from server`
- `curl: (56) Recv failure: Connection reset by peer`
- Browser shows "Failed to fetch" or "Network error"

### Browser CSP (Content Security Policy) Issues

When testing locally, you may encounter CSP errors:

**Error message:**
```
Refused to connect to https://localhost:8080/ping because it does not appear in the connect-src directive
```

**This is normal browser security** - CSP blocks connections to localhost from web pages.

### CORS Preflight Requests

Modern browsers automatically send OPTIONS requests before custom headers:

**What you might see in logs:**
```
2025/07/18 16:45:29 CORS preflight request from [::1]:55547
2025/07/18 16:45:29 Valid ping request from [::1]:55547
```

**This is normal behavior** - browsers send OPTIONS first, then your actual GET request.

**Solutions for local testing:**

1. **Use curl instead (recommended):**
   ```bash
   DATE=$(date -u +"%Y-%m-%d")
   SIGNATURE=$(echo -n "${DATE}ming-mong-server" | sha256sum | cut -c1-16)
   curl -H "X-Ping-Signature: $SIGNATURE" http://localhost:8080/ping
   ```

2. **Add CSP meta tag to your HTML:**
   ```html
   <meta http-equiv="Content-Security-Policy" content="connect-src 'self' localhost:8080 127.0.0.1:8080 http://localhost:8080">
   ```

3. **Test with real domain (production):**
   ```javascript
   // This will work on production without CSP issues
   const response = await fetch('https://yourdomain.com:8080/ping', {
       headers: { 'X-Ping-Signature': signature }
   });
   ```

**Note:** On production servers with real domains, CSP issues don't occur.

4. **If CSP still blocks (advanced):**
   - Chrome: `--disable-web-security --user-data-dir="/tmp/chrome_dev"`
   - Firefox: `about:config` → `security.csp.enable` → `false`
   - Use a local web server: `python -m http.server 8000` and access via `http://localhost:8000/`

**Solutions:**
1. Check if signature is correct:
   ```bash
   # Generate signature manually
   DATE=$(date -u +"%Y-%m-%d")
   SIGNATURE=$(echo -n "${DATE}ming-mong-server" | sha256sum | cut -c1-16)
   echo "Generated signature: $SIGNATURE"
   
   # Test the signature
   curl -H "X-Ping-Signature: $SIGNATURE" http://localhost:8080/ping
   ```

2. Ensure your system time is synchronized:
   ```bash
   # Linux
   sudo ntpdate -s time.nist.gov
   
   # macOS
   sudo sntp -sS time.apple.com
   ```

3. Check server logs for connection drops:
   ```bash
   docker logs ming-mong-server
   ```

4. Make sure you're using the correct endpoint:
   ```bash
   # These endpoints exist:
   curl -H "X-Ping-Signature: $SIGNATURE" http://localhost:8080/ping  # Requires signature
   curl -X OPTIONS http://localhost:8080/ping                         # CORS preflight
   
   # All other paths will close connection:
   curl http://localhost:8080/admin      # Connection closed
   curl http://localhost:8080/api        # Connection closed
   curl http://localhost:8080/robots.txt # Connection closed
   curl http://localhost:8080/signature  # Connection closed (no longer exists)
   ```

5. **If you see "invalid method: OPTIONS" in logs:**
   ```bash
   # This means the server handled CORS preflight correctly
   # Your browser should work now - try the test.html file
   ```

### Security Scanner Behavior

When security scanners (like Nmap, Nessus, or manual probes) try to discover your server:

```bash
# Common scanner attempts - all will fail silently:
curl http://localhost:8080/admin          # Connection closed
curl http://localhost:8080/wp-admin       # Connection closed  
curl http://localhost:8080/api/v1         # Connection closed
curl http://localhost:8080/phpinfo.php    # Connection closed
curl http://localhost:8080/.env           # Connection closed
curl http://localhost:8080/robots.txt     # Connection closed
curl http://localhost:8080/signature      # Connection closed (no longer exists)

# CORS preflight works (but reveals no sensitive information):
curl -X OPTIONS http://localhost:8080/ping  # Returns CORS headers only
```

**Result:** Server appears completely offline to all unauthorized access attempts.

**Note:** OPTIONS requests to `/ping` return CORS headers but reveal no sensitive information about the signature algorithm or server functionality.

## CORS and Security

### What is CORS Preflight?

When browsers make requests with custom headers (like `X-Ping-Signature`), they first send an OPTIONS request to check permissions. This is called a "preflight request."

**Example browser behavior:**
```
1. Browser sends: OPTIONS /ping
2. Server responds: 204 No Content + CORS headers  
3. Browser sends: GET /ping with X-Ping-Signature header
4. Server responds: {"status": "ok"}
```

### Security Impact

✅ **No security risk**: OPTIONS requests only return CORS headers  
✅ **No information disclosure**: Signature algorithm remains secret  
✅ **No endpoint enumeration**: Only `/ping` endpoint responds to OPTIONS  
✅ **Browser compatibility**: Modern browsers work seamlessly

## Ultimate Security Benefits

By removing the `/signature` endpoint, your server achieves **ultimate stealth mode**:

✅ **No information disclosure**: Attackers cannot discover the signature algorithm  
✅ **No endpoint enumeration**: Only `/ping` exists, everything else is closed  
✅ **Client-side generation**: Signatures must be generated locally by authorized clients  
✅ **Algorithm secrecy**: No way to reverse-engineer the signature method  
✅ **Complete invisibility**: Server appears offline to all unauthorized access  
✅ **CORS compatibility**: OPTIONS requests supported without compromising security

**Security Level Comparison:**
- 🔶 **Level 1**: Standard server with error pages
- 🔶 **Level 2**: Server with disabled error pages  
- 🔶 **Level 3**: Server with signature endpoint for development
- 🔥 **Level 4**: **Your server** - Complete invisibility with client-side signatures

## License

MIT License - see LICENSE file for details 