git submodule update --init --recursive

# setup tarantool
curl http://tarantool.org/dist/public.key | sudo apt-key add -
sudo echo "deb http://tarantool.org/dist/master/ubuntu/ `lsb_release -c -s` main" | sudo tee -a /etc/apt/sources.list.d/tarantool.list
sudo apt-get update > /dev/null
sudo apt-get -q -y install tarantool tarantool-dev

# test
cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo
make
make test
