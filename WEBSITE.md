# 官网维护与域名绑定

官网地址：https://voncoding.github.io/OpenLaunchpad/

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

本地预览，在仓库根目录运行：

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory docs
```

然后打开 `http://127.0.0.1:4173/`。资源均使用相对路径，可同时适配 GitHub Pages 项目路径和自定义域名。

## 更新应用版本

当前下载按钮指向已发布的 **v1.0.0**，该公开 ZIP 仅含 Apple Silicon（arm64）版本；不要将源码或本地构建支持的架构误写成安装包支持的架构。界面图片是 **v1.1 开发版** 的示例应用展示，不含用户桌面或个人应用列表。

发布新版安装包后，再同步修改 `docs/index.html` 中的下载链接、版本说明、发布说明链接和开发预览文案。请保留稳定版与未发布功能的区分。

## 绑定自己的域名

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
