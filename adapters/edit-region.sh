# Invoked with bash and the geometry returned by slurp.
set -eu -o pipefail
umask 077
pictures=$(xdg-user-dir PICTURES) || pictures=
directory=${pictures:-"$HOME/Pictures"}/Screenshots
mkdir -p -- "$directory"
# Satty expands strftime placeholders when the user chooses Save.
output="${directory//%/%%}/Screenshot-$(date +%Y%m%d-%H%M%S-%N)-$$.png"
grim -t png -g "$1" - | satty --filename - --output-filename "$output" --copy-command 'wl-copy --type image/png'
