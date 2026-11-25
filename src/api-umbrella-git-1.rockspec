package = "api-umbrella"

version = "git-1"
source = {
  url = "git+https://github.com/NREL/api-umbrella.git"
}

dependencies = {
  "argparse ~> 0.7.2",
  "bcrypt ~> 2.3",
  "dkjson ~> 2.11",
  "inspect ~> 3.1.3",
  "lapis ~> 1.20.0",
  "libcidr-ffi ~> 1.0.0",
  "lua-nanoid ~> 1.1.1",
  "lua-resty-http ~> 0.18.0",
  "lua-resty-mail ~> 1.2.0",
  "lua-resty-mlcache ~> 2.8.0",
  "lua-resty-nettle ~> 2.1",
  "lua-resty-openidc ~> 1.7.6",
  "lua-resty-session ~> 3.10",
  "lua-resty-txid ~> 1.0.0",
  -- Hold at 1.1 until this new issue with 1.2 is fixed:
  -- https://github.com/bungle/lua-resty-uuid/pull/6
  "lua-resty-uuid ~> 1.1",
  "lua-resty-validation ~> 2.7",
  "luajit-zstd ~> 0.2.3",
  "lualdap ~> 1.4.0",
  "luaposix ~> 37.0",
  "luautf8 ~> 0.3.0",
  "lustache ~> 1.3.1",
  "lyaml ~> 6.2.10",
  "penlight ~> 1.15.0",
  -- Hold at 1.16 for now, since some of our stuff touching pgmoon internals
  -- doesn't appear compatible yet.
  "pgmoon ~> 1.16.0",
  "psl ~> 0.3",
  "shell-games ~> 1.1.0",
}

build = {
  type = "builtin",
  modules = {},
}
