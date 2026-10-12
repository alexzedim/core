#!/bin/sh
# gitlab-ce 19.0.1 with external DB/Redis: the omnibus recipe writes a
# path-string placeholder into the registry signing key (registry_key_path)
# on every `gitlab-ctl reconfigure`, which breaks JwtController
# (OpenSSL::PKey::RSAError "Neither PUB key nor PRIV key") and flaps the
# container registry. Re-materialize the real keypair from the stable copy
# and restart BOTH consumers: puma reads the key at boot, the registry loads
# rootcertbundle at boot (a stale in-memory cert silently 401s every token).
#
# RUN AFTER EVERY `docker exec gitlab gitlab-ctl reconfigure`.
# Lives in the git_config volume -> survives container recreation.
set -e
DIR=/etc/gitlab/registry-auth
KEY=$DIR/registry-auth.key
CRT=$DIR/registry-auth.crt
[ -f "$DIR/stable.key" ] && [ -f "$DIR/stable.crt" ] || {
    echo "missing $DIR/stable.{key,crt}" >&2
    exit 1
}
cp "$DIR/stable.key" "$KEY"
cp "$DIR/stable.crt" "$CRT"
chown git:git "$KEY"
chmod 600 "$KEY"
chown registry:registry "$CRT"
chmod 644 "$CRT"
gitlab-ctl restart puma
gitlab-ctl restart registry
i=0
while [ $i -lt 40 ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5100/v2/ || true)
    # /jwt/auth goes through puma: 401 (warm, anonymous) vs 502/000 (cold).
    jwt=$(curl -s -o /dev/null -w '%{http_code}' 'https://gitlab.cmnw.ru/jwt/auth?service=container_registry&scope=repository:test:pull' || true)
    [ "$code" = "401" ] && [ "$jwt" = "401" ] && break
    sleep 2
    i=$((i + 1))
done
if [ "$code" = "401" ] && [ "$jwt" = "401" ]; then
    echo "registry auth keypair restored; /v2/ and /jwt/auth answer 401 (healthy)"
else
    echo "WARNING: registry did not come up (/v2/: $code, /jwt/auth: $jwt)" >&2
    exit 1
fi
