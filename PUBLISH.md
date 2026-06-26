# 发布到 GitHub 指南

## 方法一：使用 GitHub CLI（推荐）

### 1. 登录 GitHub

```bash
gh auth login
```

按提示操作：
- 选择 GitHub.com
- 选择 HTTPS 或 SSH
- 选择登录方式（浏览器或 token）

### 2. 创建仓库并推送

```bash
# 进入项目目录
cd /Users/fei/WorkBuddy/2026-06-27-02-28-40/traffic-limiter

# 初始化 Git
git init
git add .
git commit -m "Initial commit: Traffic Limiter v1.0.0"

# 创建 GitHub 仓库
gh repo create traffic-limiter --public --source=. --push
```

### 3. 创建 Release

```bash
# 创建 tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# 创建 Release
gh release create v1.0.0 traffic-limiter-v1.0.0.tar.gz \
  --title "Traffic Limiter v1.0.0" \
  --notes "首个正式版本"
```

---

## 方法二：手动在 GitHub 网站操作

### 1. 在 GitHub 创建仓库

1. 访问 https://github.com/new
2. 仓库名: `traffic-limiter`
3. 描述: `自动监控云主机流量使用情况，在流量接近限制时自动限速`
4. 选择 Public
5. 勾选 "Add a README file"
6. 点击 "Create repository"

### 2. 推送代码

```bash
cd /Users/fei/WorkBuddy/2026-06-27-02-28-40/traffic-limiter
git init
git add .
git commit -m "Initial commit: Traffic Limiter v1.0.0"
git remote add origin https://github.com/pengfei/traffic-limiter.git
git push -u origin main
```

### 3. 上传 Release

1. 访问 https://github.com/pengfei/traffic-limiter/releases/new
2. Tag: `v1.0.0`
3. Title: `Traffic Limiter v1.0.0`
4. 上传 `traffic-limiter-v1.0.0.tar.gz`
5. 点击 "Publish release"

---

## 推荐：使用方法一（自动化）

如果你想让我帮你执行，请先运行：

```bash
gh auth login
```

然后告诉我，我来帮你完成剩余步骤。
