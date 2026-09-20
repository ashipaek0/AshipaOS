# pax-utils 1.3.7 source equivalence evidence

Comparison performed against the authoritative upstream GitHub repository:

- Gentoo distfile: `https://dev.gentoo.org/~sam/distfiles/app-misc/pax-utils/pax-utils-1.3.7.tar.xz`
- Gentoo distfile SHA-256: `108362d29668d25cf7b0cadc63b15a4c1cfc0dbc71adc151b33c5fe7dece939`
- GitHub equivalent: `https://github.com/gentoo/pax-utils` tag `v1.3.7`
- GitHub tag peeled commit: `d49fa503588cb9a89eda7eb7141b65507fa126ce`

Both archives were extracted with their single top-level directory removed and compared by
relative path and SHA-256:

- Gentoo distfile files: `63`
- GitHub tag archive files: `58`
- Common files: `58`
- Differing common files: `0`
- Gentoo-only files: `man/dumpelf.1`, `man/pax-utils.docbook`, `man/pspax.1`, `man/scanelf.1`, `man/scanmacho.1`
- GitHub-only files: none

The common build inputs are byte-identical, including `meson.build`, `meson_options.txt`,
and `version.h.in`. The five Gentoo-only files are generated/distributed manpage artifacts;
their corresponding DocBook sources are in the 58 byte-identical common files. This supports
using the Gentoo distfile as the same pax-utils 1.3.7 upstream source required by CoreELEC.

The CoreELEC package override is CI-only and changes only `PKG_SHA256` and `PKG_URL` after
CoreELEC archive extraction. The exact override content is:

```text
PKG_SHA256="108362d29668d25cf7b0cadc63b15a4c1cfc0dbc71adc151b33c5fe7dece939"
PKG_URL="https://dev.gentoo.org/~sam/distfiles/app-misc/pax-utils/pax-utils-1.3.7.tar.xz"
```

Override content SHA-256 (including the trailing newline):
`02c1539f4b22ac01f5718f838433b6c920fd4932a7bacf4478279b4c7cf8dca7`

The override preserves `PKG_VERSION="1.3.7"`,
`PKG_DEPENDS_HOST="toolchain:host"`, and
`PKG_MESON_OPTS_HOST="-Duse_libcap=disabled"`. The original CoreELEC archive and
Dockerfile hashes remain in `build/coreelec/pin.json` and are not changed.
