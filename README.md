hubot-chatwork
==============

A Hubot adapter for chatwork.

## Installation

1. Install `hubot-chatwork`.
  ```sh
npm install -g git+https://github.com/kunikada/hubot-chatwork.git
yo hubot --adapter chatwork
  ```

2. Set environment variables.
  ```sh
export HUBOT_CHATWORK_TOKEN="DEADBEEF" # see http://developer.chatwork.com/ja/authenticate.html
export HUBOT_CHATWORK_INTERVAL_SEC="10" # option (default: 5)
  ```

3. Run hubot with chatwork adapter.
  ```sh
bin/hubot -a chatwork
  ```

## License
The MIT License. See `LICENSE` file.
