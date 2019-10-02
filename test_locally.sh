set -e

echo "Builtin server"
echo "--------------------"
echo ""
SERVER_TYPE=builtin ./.rocks/bin/luatest

echo "Nginx server"
echo "--------------------"
echo ""
honcho start -f ./test/Procfile.test.nginx
