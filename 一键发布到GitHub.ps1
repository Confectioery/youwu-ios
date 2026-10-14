# ============================================================
# 有梧iOS版 - 一键发布到GitHub脚本
# 用法：右键 -> 使用PowerShell运行
# ============================================================

$ErrorActionPreference = "Stop"
$ProjectDir = "C:\Users\While\Desktop\youwu_ios"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  有梧iOS版 - 自动发布脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 步骤1：检查项目目录
Write-Host "[1/5] 检查项目目录..." -ForegroundColor Yellow
if (-not (Test-Path $ProjectDir)) {
    Write-Host "错误：项目目录不存在 $ProjectDir" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}
Set-Location $ProjectDir
Write-Host "  项目目录：$ProjectDir" -ForegroundColor Green
$fileCount = (Get-ChildItem -Recurse -File).Count
Write-Host "  文件数量：$fileCount" -ForegroundColor Green

# 步骤2：检查Git
Write-Host ""
Write-Host "[2/5] 检查Git环境..." -ForegroundColor Yellow
try {
    $gitVersion = git --version
    Write-Host "  $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "错误：未检测到Git，请先安装Git" -ForegroundColor Red
    Write-Host "下载地址：https://git-scm.com/download/win" -ForegroundColor Yellow
    Read-Host "按回车键退出"
    exit 1
}

# 步骤3：初始化Git仓库
Write-Host ""
Write-Host "[3/5] 初始化Git仓库..." -ForegroundColor Yellow
if (-not (Test-Path ".git")) {
    git init
    Write-Host "  Git仓库已初始化" -ForegroundColor Green
} else {
    Write-Host "  Git仓库已存在，跳过初始化" -ForegroundColor Green
}

# 步骤4：提交代码
Write-Host ""
Write-Host "[4/5] 提交代码..." -ForegroundColor Yellow
git add .
git commit -m "init: 有梧iOS版 v1.1.0" --allow-empty
$commitCount = git rev-list --count HEAD
Write-Host "  已提交，共 $commitCount 个提交" -ForegroundColor Green

# 步骤5：生成推送命令
Write-Host ""
Write-Host "[5/5] 生成推送命令..." -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  接下来需要你手动操作：" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "第1步：创建GitHub仓库" -ForegroundColor White
Write-Host "  1. 打开 https://github.com/new" -ForegroundColor Gray
Write-Host "  2. Repository name 填：youwu_ios" -ForegroundColor Gray
Write-Host "  3. 选择 Public（公开，免费）" -ForegroundColor Gray
Write-Host "  4. 不要勾选 README / .gitignore / license" -ForegroundColor Gray
Write-Host "  5. 点击 Create repository" -ForegroundColor Gray
Write-Host ""
Write-Host "第2步：复制下面的命令，在本窗口粘贴执行" -ForegroundColor White
Write-Host ""
Write-Host "  git remote add origin https://github.com/你的用户名/youwu_ios.git" -ForegroundColor Yellow
Write-Host "  git branch -M main" -ForegroundColor Yellow
Write-Host "  git push -u origin main" -ForegroundColor Yellow
Write-Host ""
Write-Host "  （把 你的用户名 替换成你的GitHub用户名）" -ForegroundColor Gray
Write-Host ""
Write-Host "第3步：推送成功后，去Codemagic构建ipa" -ForegroundColor White
Write-Host "  详细步骤见 桌面\\youwu_ios\\构建指南.md" -ForegroundColor Gray
Write-Host ""
Read-Host "按回车键退出"
