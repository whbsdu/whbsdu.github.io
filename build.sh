# nohup sh build.sh 2>&1 > ./log/server.log &
hugo server -t even --bind= --port=8080 -w
