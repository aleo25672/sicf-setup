# Publish to Origin `evolver/sicf-setup`

The cloud agent cannot push to this repo (token scoped to the CTS workspace only).
From a machine where you are signed in to Origin:

```bash
# Option A — from this CTS repo (after pull)
git fetch origin sicf-setup-main
git push https://origin.cursor.com/evolver/sicf-setup.git origin/sicf-setup-main:main

# Option B — subtree from current tree
git subtree split --prefix=sicf-setup -b sicf-setup-main
git push https://origin.cursor.com/evolver/sicf-setup.git sicf-setup-main:main
```

Then in abapGit: online repo → `https://origin.cursor.com/evolver/sicf-setup.git` → package `ZEVO_SICF`.
