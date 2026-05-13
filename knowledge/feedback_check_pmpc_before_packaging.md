---
name: Check Patch My PC catalog before packaging any app
description: Before starting any new SCCM packaging work, verify PMPC doesn't already support the app; if they do, stop and tell the user
type: feedback
originSessionId: 28b76f76-692b-4d1c-a586-796ae4521e09
---
Before doing ANY packaging work for a newly requested app, fetch https://patchmypc.com/supported-products and check whether the requested app (or its publisher) appears in the catalog. If it does, stop and tell the user "<app> is a PMPC app, install it from there" — do not proceed with scripting, winget research, or source staging.

**Why:** PMPC maintains install + update packaging for every app in their catalog. Rolling a custom SCCM package for a PMPC-supported app duplicates effort, creates a parallel package that will drift from the PMPC-managed baseline, and misses automatic version updates PMPC publishes.

**How to apply:** First step of every new app packaging request. Use WebFetch on https://patchmypc.com/supported-products with a prompt like "Does this page list <app name> or <publisher>?". Only proceed to packaging (winget / MSI / EXE research) after confirming the app is NOT in the PMPC catalog. Catalog matches should be reported to the user up front, not after work has started.
