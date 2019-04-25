echo "Builtin server"
echo "--------------------"
echo ""
SERVER_TYPE=builtin ./test/http.test.lua

echo "Nginx server"
echo "--------------------"
echo ""
honcho start -f ./test/Procfile.test.nginx
