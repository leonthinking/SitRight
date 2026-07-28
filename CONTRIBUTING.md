# 参与贡献

感谢你改进 SitRight。开始前请先阅读 `README.md` 和 `AGENTS.md`。

## 开发约束

- 使用 Swift 6 和 macOS 14+。
- 修改 Xcode 配置时编辑 `project.yml`，不要提交生成的 `SitRight.xcodeproj`。
- 保持 App Group `973KFG9CL9.com.leon.SitRight`、App/Widget bundle id 和
  已有 Widget kind 稳定，除非变更明确包含兼容方案。
- 不提交 `Marketing/`、`.build/`、`build/`、DMG、私钥、令牌、用户目录或
  真实活动数据。
- 用户可见文案使用当前中文产品语言，并同步检查 README。

## 验证

业务逻辑变更至少运行：

```bash
swift test --disable-sandbox
```

涉及 Widget、App Group、签名、打包或 `project.yml` 时还要运行：

```bash
./Scripts/build_app.sh
```

提交 Pull Request 时请说明行为变化、验证结果、未完成的人工检查和兼容性影响。
贡献按仓库根目录的 MIT License 提交；第三方代码继续遵循各自许可。
