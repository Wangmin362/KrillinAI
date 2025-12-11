# 构建Server
buildServer:
	go build -o krillin-ai cmd/server/main.go

# 运行Server
runServer: buildServer
	./krillin-ai

# 清理
clean:
	rm -f krillin-ai