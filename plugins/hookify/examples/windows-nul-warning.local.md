---
name: warn-windows-nul
enabled: true
event: bash
pattern: "[12&]?>+\\s*nul\\b"
action: warn
---

⚠️ **Windows `nul` device detected**

Redirecting to `nul` is a Windows-specific pattern that doesn't work on Unix systems.

❌ **Wrong (Windows only):**
```bash
command > nul 2>&1
```

✅ **Correct (cross-platform):**
```bash
command > /dev/null 2>&1
```

Consider using `/dev/null` instead for cross-platform compatibility.
