{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/basics/
  env.GREET = "Omnigres";

  # https://devenv.sh/packages/
  packages = with pkgs; [
    bcc
    clang
    cmake
    curl
    doxygen
    flex
    git
    libuv
    openssl
    perl
    pkg-config
    postgresql_16
    python3
    python3Packages.pip
    python3Packages.virtualenv
    readline
    zlib
  ];

  # https://devenv.sh/scripts/
  scripts.hello.exec = "echo Hello from $GREET";

  enterShell = ''
    export PATH=$PATH:${pkgs.postgresql_16.debug}/lib/debug

    bar=$(printf '=%.0s' {1..79})
    echo $bar

    cmake --version|grep version|sed 's|version ||'
    clang --version|grep version|sed 's|version ||'
    curl --version|grep curl|cut -d' ' -f1-2
    echo doxygen $(doxygen --version|cut -d' ' -f1)
    flex --version
    git --version|sed 's|version ||'
    openssl version|cut -d' ' -f1-2
    echo perl $(perl --version|grep ^This|cut -d'(' -f2|cut -d')' -f1)
    echo pkg-config $(pkg-config --version)
    psql --version|cut -d' ' -f1,3
    echo shellcheck $(shellcheck --version|grep ^version|cut -d' ' -f2) ;# pre-commit hook

    echo $bar
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    git --version | grep "2.42.0"
  '';

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/languages/
  languages = {
    c.enable = true;
    nix.enable = true;
  };

  # https://devenv.sh/pre-commit-hooks/
  pre-commit.hooks.shellcheck.enable = true;

  # https://devenv.sh/processes/
  # processes.ping.exec = "ping example.com";

  # See full reference at https://devenv.sh/reference/options/
}
