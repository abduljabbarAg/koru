# Vendored: glen

The on-device inference engine, vendored so the APK build does not depend on
glen being reachable.

## Why it is here rather than cloned

CI could not clone glen because the repository is private, and a token scoped to
this repository cannot read another one. Rather than keep a public window open,
the source is committed here at a pinned revision.

## Why pinning is right, not just convenient

Koru bundles this binary into its release APK. A build that tracked a moving
branch would mean the same version of the app shipped different inference code
depending on when it built. The commit is pinned so a build is reproducible.

## Revision

    00dee2f23d2950df2062d1b4a9da85aec55b0909
    Track the assets/models directory

## Updating

    git clone https://github.com/AbduljabbarBXR/glen.git /tmp/glen
    cd /tmp/glen && git checkout <new-revision>
    rm -rf /path/to/koru/third_party/glen
    cp -r /tmp/glen /path/to/koru/third_party/glen
    rm -rf /path/to/koru/third_party/glen/.git
    echo <new-revision> > /path/to/koru/third_party/GLEN_COMMIT

Re-run the benchmarks in glen's `benchmarks/P0-baseline.md` before bumping. A
newer engine is not automatically a faster one on a phone.

## Licence

glen is MIT, (c) 2026 AbduljabbarBXR. Its LICENSE file is preserved here.
