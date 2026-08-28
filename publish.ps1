# ============================================================
# publish.ps1 — 大理相册发布到 GitHub Pages(私有仓库)
# 首次运行:初始化仓库 + 强制设置身份 + 提交 + 创建私有远程 + push + 启用 Pages
# 之后运行:只提交 + 推送变更
# ============================================================

$ErrorActionPreference = 'Stop'
$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir

function Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  [X]  $msg" -ForegroundColor Red; exit 1 }

# ---------- 0. 检查 git ----------
Step "检查 git"
$gitVer = git --version 2>$null
if (-not $gitVer) { Fail "未检测到 git，请先安装 Git for Windows" }
Ok "$gitVer"

# ---------- 1. 检查 gh CLI(复用聪哥已有) ----------
Step "检查 GitHub CLI (gh)"
$localGhCandidates = @(
    (Join-Path $ProjectDir "tools\gh\bin"),
    "D:\Trae\Life\学习跟踪系统\tools\gh\bin"
)
foreach ($cand in $localGhCandidates) {
    if (Test-Path $cand) {
        $env:Path = "$cand;$env:Path"
        break
    }
}
$ghPath = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghPath) {
    Warn "gh 未找到，正在通过 winget 安装..."
    winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Fail "gh 安装失败(winget 退出码 $LASTEXITCODE)，请手动安装：https://cli.github.com" }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $ghPath = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghPath) { Fail "gh 已安装但仍无法调用，请重启 PowerShell 后重试" }
}
Ok "gh 已就绪：$((gh --version) -split "`n" | Select-Object -First 1)"

# ---------- 2. 检查 gh 登录状态 ----------
Step "检查 GitHub 登录状态"
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Warn "尚未登录 GitHub，将打开浏览器进行 OAuth 授权..."
    gh auth login --web -h github.com -p https -s "repo,workflow,delete_repo"
    if ($LASTEXITCODE -ne 0) { Fail "gh auth login 失败" }
}
$ghUser = gh api user -q .login
Ok "已登录 GitHub：$ghUser"

# ---------- 3. 区分首次 / 后续运行 ----------
$isFirstRun = -not (Test-Path ".git")
$repoName = "dali-grownup-album-2026"

# ---------- 4. git init(仅首次) ----------
if ($isFirstRun) {
    Step "初始化 git 仓库"
    git init -b main | Out-Null
    Ok "已初始化 main 分支"
}

# ---------- 5. 强制配置提交身份(覆盖 Git 占位值) ----------
Step "配置提交身份"
git config user.name "$ghUser"
git config user.email "$ghUser@users.noreply.github.com"
Ok "user.name  = $(git config user.name)"
Ok "user.email = $(git config user.email)"

# ---------- 6. 检查关键文件 ----------
Step "检查发布文件"
if (-not (Test-Path "index.html")) { Fail "缺少 index.html" }
if (-not (Test-Path "js/tailwind.min.js")) { Fail "缺少 js/tailwind.min.js" }
$sizeMB = [math]::Round((Get-Item "index.html").Length / 1MB, 2)
Ok "index.html ($sizeMB MB) + js/tailwind.min.js 均存在"

# ---------- 7. 提交本地变更(必须先有 commit,gh repo create --push 才不会卡) ----------
Step "提交本地变更"
git add -A
$status = git status --short
if ($status) {
    $commitMsg = if ($isFirstRun) { "init: 女儿十八岁大理成人礼纪念画册首版" } else { "update: $(Get-Date -Format 'yyyy-MM-dd HH:mm') 同步本地变更" }
    git commit -m "$commitMsg" | Out-Null
    Ok "已提交：$commitMsg"
} else {
    Warn "无变更需要提交"
}

# ---------- 8. 创建 / 配置远程仓库(仅首次) ----------
if ($isFirstRun) {
    Step "配置远程仓库 $repoName"
    $repoExists = gh repo view "$ghUser/$repoName" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Warn "仓库不存在，创建私有仓库..."
        # 注意:不带 --push,避免 gh CLI 试图自行推送产生交互
        gh repo create $repoName --private --description "女儿十八岁大理成人礼纪念画册(私有·家庭相册)" --source . 2>$null
        if ($LASTEXITCODE -ne 0) { Fail "gh repo create 失败" }
    } else {
        Warn "仓库已存在，添加远程..."
    }
    # 确保 upstream remote 存在
    $remoteUrl = "https://github.com/$ghUser/$repoName.git"
    $existingRemote = git remote get-url upstream 2>$null
    if ($LASTEXITCODE -ne 0) {
        git remote add upstream $remoteUrl
    } elseif ($existingRemote -ne $remoteUrl) {
        git remote set-url upstream $remoteUrl
    }
    Ok "远程已配置：https://github.com/$ghUser/$repoName"
}

# ---------- 9. 推送到 main ----------
Step "推送到 main"
$pushOutput = git push -u upstream main 2>&1
if ($LASTEXITCODE -ne 0) {
    # 失败原因可能是仓库为空(gh repo create 后 main 不存在)——先确保 main 分支在远端存在
    if ($pushOutput -match "could not find" -or $pushOutput -match "not found") {
        Warn "上游 main 不存在，先推送一次建立..."
        git push upstream HEAD:main --force 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "推送失败,请检查 gh auth status 是否仍有效" }
    } else {
        Fail "推送失败:$pushOutput"
    }
}
Ok "已推送到 main 分支"

# ---------- 10. 启用私有 GitHub Pages(仅首次) ----------
if ($isFirstRun) {
    Step "启用私有 GitHub Pages(main / root)"
    gh repo edit "$ghUser/$repoName" --enable-pages --pages-source-branch main --pages-source-path / --pages-visibility private 2>$null
    if ($LASTEXITCODE -ne 0) {
        Warn "gh repo edit --pages-visibility 私有 Pages 失败，尝试 REST API 降级方案..."
        # 1) 启用 Pages
        gh api -X POST "repos/$ghUser/$repoName/pages" -f "source[branch]=main" -f "source[path]=/" 2>$null | Out-Null
        # 2) 设置为私有可见性
        gh api -X PUT "repos/$ghUser/$repoName/pages" -f "source[branch]=main" -f "source[path]=/" -f "visibility=private" 2>$null | Out-Null
    }
    Start-Sleep -Seconds 3
}

# ---------- 11. 输出最终 URL ----------
$pagesUrl = "https://$ghUser.github.io/$repoName/"
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  发布完成！" -ForegroundColor Green
Write-Host "  仓库地址：  https://github.com/$ghUser/$repoName" -ForegroundColor White
Write-Host "  Pages 地址：$pagesUrl" -ForegroundColor White
Write-Host "  访问权限：  私有(只有你可访问，或邀请的协作者)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "提示：第一次访问 Pages 可能需要 1~3 分钟生效。" -ForegroundColor Yellow
Write-Host "      之后每次改动，再次运行本脚本即可同步。" -ForegroundColor Yellow