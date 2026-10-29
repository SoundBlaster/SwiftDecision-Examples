# Endless Answers website

Static landing, privacy and support pages for `https://egormerkushev.ru/8ball/`. The site uses only local assets and no analytics scripts. Preview locally with `python3 -m http.server --directory website/8ball 8000`.

The FTPS workflow follows the 7of10 deployment pattern and is scoped to `/www/egormerkushev.ru/8ball`. Before use, configure a GitHub environment named `FTP` in this repository with variables `FTP_HOST`, `FTP_PORT` (`21`), `FTP_USER`, `FTP_REMOTE_ROOT` (the exact path above), and secret `FTP_PASSWORD`. The similarly named environment in the 7of10 repository is separate; its secrets are not inherited. The workflow verifies the TLS certificate, does not request deletion of remote files, and compares published files with the checked-out commit.

Review privacy statements against the release candidate and the provider's practices before publication. Update the site whenever those practices change.
