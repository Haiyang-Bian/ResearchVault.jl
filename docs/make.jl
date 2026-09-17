using Documenter
using ResearchVault

makedocs(
    sitename="ResearchVault.jl",
    modules=[ResearchVault],
    format=Documenter.HTML(prettyurls=false),
    pages=[
        "Home" => "index.md",
        "安装与连接" => "installation.md",
        "成员身份" => "member-auth.md",
        "科研工作流" => "workflow.md",
        "错误与离线" => "errors.md",
        "API 概览" => "api.md",
    ],
)

deploydocs(repo="github.com/Haiyang-Bian/ResearchVault.jl.git", devbranch="main")
