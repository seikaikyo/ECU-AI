const http = require('http');
const https = require('https');
const net = require('net');
const url = require('url');
const fs = require('fs');
const path = require('path');

// 配置文件支援
const CONFIG_FILE = path.join(__dirname, 'proxy_config.json');
const DEFAULT_CONFIG = {
    port: 8888,
    targetHost: 'claude.ai',
    logLevel: 'info',
    timeout: 30000,
    userAgent: 'Claude-Proxy/1.0'
};

// 載入配置
function loadConfig() {
    try {
        if (fs.existsSync(CONFIG_FILE)) {
            const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
            return { ...DEFAULT_CONFIG, ...config };
        }
    } catch (error) {
        console.warn('配置文件載入失敗，使用預設設定:', error.message);
    }
    return DEFAULT_CONFIG;
}

// 日誌功能
function log(level, message, ...args) {
    const timestamp = new Date().toISOString();
    const prefix = `[${timestamp}] [${level.toUpperCase()}]`;
    console.log(prefix, message, ...args);
}

class SmartClaudeProxy {
    constructor(config = {}) {
        this.config = { ...loadConfig(), ...config };
        this.port = this.config.port;
        this.server = null;
        
        // 驗證配置
        this.validateConfig();
    }
    
    validateConfig() {
        if (!Number.isInteger(this.port) || this.port < 1 || this.port > 65535) {
            throw new Error(`無效的連接埠號: ${this.port}`);
        }
        if (!this.config.targetHost || typeof this.config.targetHost !== 'string') {
            throw new Error('目標主機設定無效');
        }
    }

    start() {
        this.server = http.createServer((req, res) => {
            this.handleHttpRequest(req, res);
        });

        // 處理 HTTPS CONNECT 請求
        this.server.on('connect', (req, socket, head) => {
            this.handleConnectRequest(req, socket, head);
        });

        this.server.listen(this.port, 'localhost', () => {
            log('info', `🚀 智能 Claude 代理伺服器啟動在 http://localhost:${this.port}`);
            log('info', '');
            log('info', '設定方式：');
            log('info', `export HTTP_PROXY=http://localhost:${this.port}`);
            log('info', `export HTTPS_PROXY=http://localhost:${this.port}`);
            log('info', '');
            log('info', '或者：');
            log('info', `npm config set proxy http://localhost:${this.port}`);
            log('info', `npm config set https-proxy http://localhost:${this.port}`);
        });
        
        this.server.on('error', (error) => {
            log('error', '伺服器錯誤:', error.message);
            if (error.code === 'EADDRINUSE') {
                log('error', `連接埠 ${this.port} 已被使用`);
            }
        });
    }

    handleHttpRequest(req, res) {
        try {
            const reqUrl = url.parse(req.url);
            log('info', `📤 HTTP 請求: ${req.method} ${req.url}`);

            // 輸入驗證
            if (!req.url || !req.method) {
                log('warn', '無效的請求');
                res.writeHead(400);
                res.end('Bad Request');
                return;
            }

            // 如果是 Anthropic API 請求，重定向到 claude.ai
            if (reqUrl.hostname === 'api.anthropic.com') {
                log('info', '🔀 重定向 API 請求到 claude.ai');
                this.redirectToClaudeAi(req, res);
            } else {
                log('info', '📡 直接代理請求');
                this.proxyDirectly(req, res);
            }
        } catch (error) {
            log('error', 'HTTP 請求處理錯誤:', error.message);
            res.writeHead(500);
            res.end('Internal Server Error');
        }
    }

    handleConnectRequest(req, socket, head) {
        try {
            // 改進的 URL 分割邏輯，支援 IPv6
            const urlParts = this.parseHostPort(req.url);
            if (!urlParts) {
                log('warn', `無效的 CONNECT URL: ${req.url}`);
                socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
                socket.end();
                return;
            }
            
            const { hostname, port } = urlParts;
            log('info', `🔐 CONNECT 請求: ${hostname}:${port}`);

            if (hostname === 'api.anthropic.com') {
                log('info', '🔀 重定向 CONNECT 到 claude.ai');
                this.connectToClaudeAi(socket, head);
            } else {
                log('info', '📡 直接建立 CONNECT 隧道');
                this.directConnect(req, socket, head);
            }
        } catch (error) {
            log('error', 'CONNECT 請求處理錯誤:', error.message);
            socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n');
            socket.end();
        }
    }
    
    parseHostPort(url) {
        if (!url) return null;
        
        // IPv6 支援
        const ipv6Match = url.match(/^\[([^\]]+)\]:(\d+)$/);
        if (ipv6Match) {
            return { hostname: ipv6Match[1], port: parseInt(ipv6Match[2]) };
        }
        
        // IPv4 和域名
        const parts = url.split(':');
        if (parts.length === 2) {
            return { hostname: parts[0], port: parseInt(parts[1]) };
        }
        
        // 預設 HTTPS 埠
        if (parts.length === 1) {
            return { hostname: parts[0], port: 443 };
        }
        
        return null;
    }

    redirectToClaudeAi(req, res) {
        // 重寫 URL 和 Host
        const newUrl = req.url.replace('api.anthropic.com', 'claude.ai');
        const options = {
            hostname: this.config.targetHost,
            port: req.url.includes('https') ? 443 : 80,
            path: url.parse(newUrl).path,
            method: req.method,
            headers: {
                ...req.headers,
                'Host': this.config.targetHost,
                'User-Agent': this.config.userAgent
            },
            timeout: this.config.timeout
        };

        // 改進的協議判斷
        const isHttps = this.isHttpsUrl(req.url) || options.port === 443;
        const protocol = isHttps ? https : http;
        const proxyReq = protocol.request(options, (proxyRes) => {
            log('info', `✅ ${this.config.targetHost} 回應: ${proxyRes.statusCode}`);
            
            // 安全標頭處理
            const safeHeaders = this.sanitizeHeaders(proxyRes.headers);
            res.writeHead(proxyRes.statusCode, safeHeaders);
            proxyRes.pipe(res);
        });
        
        proxyReq.setTimeout(this.config.timeout, () => {
            log('warn', '請求超時');
            proxyReq.destroy();
            if (!res.headersSent) {
                res.writeHead(504);
                res.end('Gateway Timeout');
            }
        });

        proxyReq.on('error', (error) => {
            log('error', `❌ ${this.config.targetHost} 請求錯誤:`, error.message);
            if (!res.headersSent) {
                res.writeHead(500);
                res.end('Proxy Error');
            }
        });

        req.pipe(proxyReq);
    }

    connectToClaudeAi(clientSocket, head) {
        const serverSocket = net.connect(443, this.config.targetHost, () => {
            log('info', `✅ 成功連接到 ${this.config.targetHost}:443`);
            clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
            if (head && head.length > 0) {
                serverSocket.write(head);
            }
            serverSocket.pipe(clientSocket);
            clientSocket.pipe(serverSocket);
        });
        
        serverSocket.setTimeout(this.config.timeout, () => {
            log('warn', 'CONNECT 連接超時');
            serverSocket.destroy();
            clientSocket.end();
        });

        serverSocket.on('error', (error) => {
            log('error', `❌ 連接 ${this.config.targetHost} 失敗:`, error.message);
            if (!clientSocket.destroyed) {
                clientSocket.write('HTTP/1.1 500 Connection Error\r\n\r\n');
                clientSocket.end();
            }
        });
        
        clientSocket.on('error', (error) => {
            log('error', '客戶端連接錯誤:', error.message);
            if (!serverSocket.destroyed) {
                serverSocket.destroy();
            }
        });
    }

    proxyDirectly(req, res) {
        const reqUrl = url.parse(req.url);
        const options = {
            hostname: reqUrl.hostname,
            port: reqUrl.port || (req.url.includes('https') ? 443 : 80),
            path: reqUrl.path,
            method: req.method,
            headers: req.headers
        };

        // 改進的協議判斷
        const isHttps = this.isHttpsUrl(req.url) || options.port === 443;
        const protocol = isHttps ? https : http;
        const proxyReq = protocol.request(options, (proxyRes) => {
            res.writeHead(proxyRes.statusCode, proxyRes.headers);
            proxyRes.pipe(res);
        });

        proxyReq.on('error', (error) => {
            log('error', '直接代理錯誤:', error.message);
            if (!res.headersSent) {
                res.writeHead(500);
                res.end('Proxy Error');
            }
        });
        
        proxyReq.setTimeout(this.config.timeout, () => {
            log('warn', '直接代理超時');
            proxyReq.destroy();
            if (!res.headersSent) {
                res.writeHead(504);
                res.end('Gateway Timeout');
            }
        });

        req.pipe(proxyReq);
    }

    directConnect(req, socket, head) {
        const urlParts = this.parseHostPort(req.url);
        if (!urlParts) {
            log('warn', `無效的直接連接 URL: ${req.url}`);
            socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
            socket.end();
            return;
        }
        
        const { hostname, port } = urlParts;
        const serverSocket = net.connect(port || 443, hostname, () => {
            socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
            if (head && head.length > 0) {
                serverSocket.write(head);
            }
            serverSocket.pipe(socket);
            socket.pipe(serverSocket);
        });
        
        serverSocket.setTimeout(this.config.timeout, () => {
            log('warn', `直接連接超時: ${hostname}:${port}`);
            serverSocket.destroy();
            socket.end();
        });

        serverSocket.on('error', (error) => {
            log('error', `直接 CONNECT 錯誤 ${hostname}:${port}:`, error.message);
            if (!socket.destroyed) {
                socket.write('HTTP/1.1 500 Connection Error\r\n\r\n');
                socket.end();
            }
        });
        
        socket.on('error', (error) => {
            log('error', '直接連接客戶端錯誤:', error.message);
            if (!serverSocket.destroyed) {
                serverSocket.destroy();
            }
        });
    }

    isHttpsUrl(url) {
        return url && (url.startsWith('https://') || url.includes(':443'));
    }
    
    sanitizeHeaders(headers) {
        const sanitized = { ...headers };
        // 移除可能的安全敏感標頭
        delete sanitized['set-cookie'];
        delete sanitized['server'];
        return sanitized;
    }
    
    stop() {
        return new Promise((resolve) => {
            if (this.server) {
                this.server.close(() => {
                    log('info', '代理伺服器已停止');
                    resolve();
                });
            } else {
                resolve();
            }
        });
    }
}

// 建立並啟動代理
const config = loadConfig();
const proxy = new SmartClaudeProxy(config);

try {
    proxy.start();
} catch (error) {
    log('error', '代理啟動失敗:', error.message);
    process.exit(1);
}

// 優雅關閉
process.on('SIGINT', async () => {
    log('info', '\n正在關閉代理伺服器...');
    try {
        await proxy.stop();
        process.exit(0);
    } catch (error) {
        log('error', '關閉時發生錯誤:', error.message);
        process.exit(1);
    }
});

process.on('SIGTERM', async () => {
    log('info', '收到 SIGTERM，正在關閉...');
    try {
        await proxy.stop();
        process.exit(0);
    } catch (error) {
        log('error', '關閉時發生錯誤:', error.message);
        process.exit(1);
    }
});

process.on('uncaughtException', (error) => {
    log('error', '未捕獲的異常:', error.message);
    log('error', error.stack);
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    log('error', '未處理的 Promise 拒絕:', reason);
    process.exit(1);
});