# 官网维护与域名绑定

官网地址：https://appledev.app/

GitHub Pages 已绑定 `appledev.app`，域名 DNS 由 Cloudflare 管理。首次访问需要先完成下面的解析配置并等待 HTTPS 证书签发。

## 发布方式

GitHub Pages 使用 `codex/website` 分支的 `/docs` 目录。修改网站时切换到该分支，提交并推送后，GitHub 会自动重新发布。仓库的 **Actions → pages build and deployment** 可以查看部署状态。

网站是静态 HTML、CSS 和 JavaScript，无需安装依赖或执行构建命令。

| 文件 | 用途 |
| --- | --- |
| `docs/index.html` | 页面文案、功能说明、下载链接、版本号 |
| `docs/styles.css` | 桌面与手机端布局 |
| `docs/site.js` | 界面预览切换与键盘操作 |
| `docs/assets/` | 应用图标和界面截图 |
| `docs/.nojekyll` | 直接发布静态文件 |
| `docs/CNAME` | 官网域名 `appledev.app`，后续部署须保留 |

本地预览，在仓库根目录运行：

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory docs
```

然后打开 `http://127.0.0.1:4173/`。资源均使用相对路径，可同时适配 GitHub Pages 项目路径和自定义域名。

## 更新应用版本

当前下载按钮指向 **v1.1.0**，公开 ZIP 为通用安装包，同时包含 Apple Silicon（arm64）与 Intel（x86_64）版本。界面图片使用示例系统应用，不含用户桌面或个人应用列表。

发布新版安装包后，再同步修改 `docs/index.html` 中的下载链接、版本说明、发布说明链接和新增功能文案。如展示未来版本的功能，须明确区分稳定版与未发布功能。

## appledev.app 的解析设置

进入 Cloudflare → `appledev.app` → DNS → Records，为名称 `@` 分别添加下表中的四条 A 记录，TTL 使用 Auto。首次接入建议将这四条记录的代理状态均设为 **DNS only（灰云）**，让 DNS 直接返回 GitHub Pages 的地址。Cloudflare 的代理状态说明见[官方文档](https://developers.cloudflare.com/dns/proxy-status/)。

如需 `www.appledev.app` 入口，再添加名称 `www`、目标 `voncoding.github.io` 的 CNAME 记录。

## 以后更换域名

先在 GitHub 绑定域名，再修改 DNS：

1. 打开仓库 **Settings → Pages → Custom domain**，填入实际域名并保存。
2. GitHub 会在网站发布目录写入 `CNAME` 文件。后续本地编辑前先拉取远端提交，保留这个文件。
3. 在域名服务商添加对应解析记录：

| 域名类型 | DNS 类型 | 记录值 |
| --- | --- | --- |
| 子域名，例如 `www` 或 `app` | CNAME | `voncoding.github.io` |
| 根域名，通常主机记录为 `@` | A | `185.199.108.153` |
| 根域名，通常主机记录为 `@` | A | `185.199.109.153` |
| 根域名，通常主机记录为 `@` | A | `185.199.110.153` |
| 根域名，通常主机记录为 `@` | A | `185.199.111.153` |

子域名的 CNAME 记录值不带 `https://`，也不带 `/OpenLaunchpad/`。根域名使用上面四条 A 记录；不要同时保留该主机记录上指向其他服务的冲突记录。

等待 DNS 检查通过和证书签发后，在 Pages 设置中启用 **Enforce HTTPS**。DNS 生效最多可能需要 24 小时。自定义域名启用后，也请同步更新本文件、README 和仓库 About 的 Website 地址。

以 GitHub 官方文档为准：[配置发布来源](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)、[管理自定义域名](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)。
