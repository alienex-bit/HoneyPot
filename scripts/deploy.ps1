param (
    [string]$DeviceID = ""
)

Write-Host "--- Starting HoneyPot Android Deployment ---" -ForegroundColor Cyan

# 1. Build APK
Write-Host "Building APK for HoneyPot..." -ForegroundColor Yellow
cd "$PSScriptRoot\..\src"
flutter build apk --debug

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter build failed." -ForegroundColor Red
    exit 1
}

# 2. Get Device ID if not provided
if ($DeviceID -eq "") {
    $devices = adb devices | Select-String -Pattern "\tdevice$"
    if ($devices.Count -eq 0) {
        Write-Host "Error: No devices connected via ADB." -ForegroundColor Red
        exit 1
    }
    $DeviceID = ($devices[0].ToString().Split("`t"))[0]
}

Write-Host "Target Device: $DeviceID" -ForegroundColor Cyan

# 3. Install APK
$apkPath = "$PSScriptRoot\..\src\build\app\outputs\flutter-apk\app-debug.apk"
Write-Host "Installing APK to $DeviceID..." -ForegroundColor Yellow
adb -s $DeviceID install -r "$apkPath"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: ADB installation failed." -ForegroundColor Red
    exit 1
}

# 4. Launch App
Write-Host "Launching HoneyPot..." -ForegroundColor Green
adb -s $DeviceID shell am start -n com.example.honeypot/com.example.honeypot.MainActivity

Write-Host "--- Deployment Complete ---" -ForegroundColor Green
