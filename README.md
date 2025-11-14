[custom]
; ACL4SSR 自定义规则模板
; 你可以直接在这里加入自己的节点（Proxy），不影响规则运行

; ==============================
; 🎯 基础规则集
; ==============================
ruleset=🎯 全球直连,https://raw.githubusercontent.com/cmliu/ACL4SSR/refs/heads/main/Clash/CFnat.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/LocalAreaNetwork.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/UnBan.list

; ==============================
; 🛑 广告拦截
; ==============================
ruleset=🛑 广告拦截,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/BanAD.list
ruleset=🍃 应用净化,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/BanProgramAD.list
ruleset=🍃 应用净化,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/adobe.list
ruleset=🍃 应用净化,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/IDM.list

; ==============================
; 📢 Google / Microsoft / Apple
; ==============================
ruleset=📢 谷歌FCM,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/GoogleFCM.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/GoogleCN.list
ruleset=Ⓜ️ 微软Bing,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Bing.list
ruleset=Ⓜ️ 微软云盘,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/OneDrive.list
ruleset=Ⓜ️ 微软服务,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Microsoft.list
ruleset=🍎 苹果服务,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Apple.list

; ==============================
; 📲 Telegram
; ==============================
ruleset=📲 电报消息,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Telegram.list

; ==============================
; 🤖 AI / OpenAI / Copilot / Claude
; ==============================
ruleset=🤖 OpenAi,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/OpenAi.list
ruleset=🤖 OpenAi,https://raw.githubusercontent.com/juewuy/ShellClash/master/rules/ai.list
ruleset=🤖 OpenAi,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/Copilot.list
ruleset=🤖 OpenAi,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/GithubCopilot.list
ruleset=🤖 OpenAi,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/Claude.list

; ==============================
; 🎵/🎮/📺 影音媒体分流
; ==============================
ruleset=🎶 网易音乐,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/NetEaseMusic.list
ruleset=📹 油管视频,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/YouTube.list
ruleset=🎥 奈飞视频,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Netflix.list
ruleset=📺 巴哈姆特,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Bahamut.list
ruleset=📺 哔哩哔哩,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/BilibiliHMT.list
ruleset=📺 哔哩哔哩,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Bilibili.list
ruleset=🌏 国内媒体,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ChinaMedia.list
ruleset=🌍 国外媒体,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ProxyMedia.list
ruleset=🌍 国外媒体,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/Emby.list

; ==============================
; 🚀 代理与直连规则
; ==============================
ruleset=🚀 节点选择,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ProxyGFWlist.list
ruleset=🚀 节点选择,https://raw.githubusercontent.com/UlinoyaPed/ShellClash/dev/lists/proxy.list
ruleset=🚀 节点选择,https://raw.githubusercontent.com/cmliu/ACL4SSR/main/Clash/CMBlog.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/UlinoyaPed/ShellClash/dev/lists/direct.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ChinaDomain.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ChinaCompanyIp.list
ruleset=🎯 全球直连,https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Download.list
ruleset=🎯 全球直连,[]GEOIP,CN

; ==============================
; 🐟 Final
; ==============================
ruleset=🐟 漏网之鱼,[]FINAL
