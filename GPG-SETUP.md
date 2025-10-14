# 🔐 GPG and git-crypt Setup Guide

This guide walks you through setting up GPG keys and git-crypt for encrypting sensitive files in the Brother Eye repository.

---

## 📋 Overview

**git-crypt** enables transparent encryption of files in a git repository. Files marked in `.gitattributes` are automatically encrypted on commit and decrypted on checkout.

**Why use this?**
- ✅ Backup your `.env.production` and VPN configs safely in git
- ✅ Share encrypted repository without exposing secrets
- ✅ Seamless workflow (encryption/decryption is automatic)
- ✅ No need to manage separate encrypted archives

---

## 🛠️ Prerequisites

```bash
# Install required packages
apt update
apt install -y gnupg git-crypt

# Verify installations
gpg --version
git-crypt --version
```

---

## 🔑 Step 1: Generate GPG Key

### Generate a New GPG Key

```bash
# Start the key generation wizard
gpg --full-generate-key
```

**Follow the prompts:**

1. **Please select what kind of key you want:**
   ```
   (1) RSA and RSA (default)
   ```
   Choose: **1**

2. **What keysize do you want?**
   ```
   (3072)
   ```
   Enter: **4096** (for maximum security)

3. **Please specify how long the key should be valid:**
   ```
   0 = key does not expire
   ```
   Enter: **0** (or set expiration like `1y` for 1 year)

4. **Is this correct?**
   Verify and enter: **y**

5. **Real name:**
   ```
   Brother Eye Admin
   ```
   (Or your actual name)

6. **Email address:**
   ```
   your-email@example.com
   ```

7. **Comment:**
   ```
   Brother Eye Media Stack
   ```
   (Optional description)

8. **Change (N)ame, (C)omment, (E)mail or (O)kay/(Q)uit?**
   Enter: **O**

9. **Enter passphrase:**
   - Choose a **strong passphrase**
   - You'll need this to unlock your private key
   - Store in password manager!

---

## 📝 Step 2: Get Your GPG Key ID

```bash
# List your GPG keys
gpg --list-secret-keys --keyid-format=long
```

**Output example:**
```
sec   rsa4096/ABCD1234EFGH5678 2025-10-12 [SC]
      1234567890ABCDEF1234567890ABCDEF12345678
uid           [ultimate] Brother Eye Admin (Brother Eye Media Stack) <your-email@example.com>
ssb   rsa4096/9876543210FEDCBA 2025-10-12 [E]
```

**Your KEY_ID is:** `ABCD1234EFGH5678` (the part after `rsa4096/`)

**Export to environment variable for easy reference:**
```bash
export GPG_KEY_ID="ABCD1234EFGH5678"
echo "export GPG_KEY_ID=\"ABCD1234EFGH5678\"" >> ~/.bashrc
```

---

## 💾 Step 3: Backup Your GPG Keys

**CRITICAL:** Store these backups in a secure location (password manager, encrypted USB, etc.)

```bash
# Export public key
gpg --armor --export $GPG_KEY_ID > ~/brother-eye-gpg-public.asc

# Export private key (KEEP THIS SECURE!)
gpg --armor --export-secret-keys $GPG_KEY_ID > ~/brother-eye-gpg-private.asc

# Verify exports
ls -lh ~/brother-eye-gpg-*.asc
```

**Store these files:**
- In your password manager (as secure notes)
- On an encrypted USB drive
- In a separate encrypted backup location
- **NEVER** commit them to git (even encrypted)

---

## 🔧 Step 4: Initialize git-crypt in Repository

```bash
# Navigate to your repository
cd /root/brother-eye-media-stack

# Initialize git-crypt
git-crypt init

# Add your GPG key to git-crypt
git-crypt add-gpg-user $GPG_KEY_ID

# Verify git-crypt status
git-crypt status
```

**Expected output:**
```
not encrypted: .gitattributes
not encrypted: .gitignore
not encrypted: GPG-SETUP.md
```

---

## 🔒 Step 5: Test Encryption

```bash
# Create a test secret file
mkdir -p secrets
echo "TEST_API_KEY=super-secret-value-12345" > secrets/test.env

# Add to git
git add secrets/test.env
git commit -m "Test: Add encrypted secret"

# Verify it's encrypted in the repository
git show HEAD:secrets/test.env
```

**You should see:** Binary gibberish (encrypted content)

**Lock the repository to verify:**
```bash
# Lock (encrypt all files)
git-crypt lock

# Try to read the file
cat secrets/test.env
```

**You should see:** Binary gibberish (file is encrypted on disk)

**Unlock to decrypt:**
```bash
git-crypt unlock

# Now you can read it
cat secrets/test.env
```

**You should see:** `TEST_API_KEY=super-secret-value-12345`

---

## 🌐 Step 6: Clone Repository on Another Machine

### Method 1: Using GPG Key (Recommended)

**On the new machine:**

```bash
# Install prerequisites
apt update && apt install -y gnupg git-crypt git

# Import your private GPG key
gpg --import ~/brother-eye-gpg-private.asc

# Trust the imported key
gpg --edit-key $GPG_KEY_ID
# In the GPG prompt, type: trust
# Choose: 5 (ultimate trust)
# Type: quit

# Clone the repository
git clone git@github.com:YOUR_USERNAME/brother-eye-media-stack.git
cd brother-eye-media-stack

# Unlock with your GPG key
git-crypt unlock

# Verify secrets are readable
cat secrets/test.env
```

### Method 2: Using Symmetric Key File (Simpler)

**On the original machine (one-time export):**

```bash
cd /root/brother-eye-media-stack

# Export a symmetric key file
git-crypt export-key ~/brother-eye-gitcrypt.key

# Backup this key file securely
# Transfer it to the new machine via secure method (scp, encrypted USB, etc.)
```

**On the new machine:**

```bash
# Clone the repository
git clone git@github.com:YOUR_USERNAME/brother-eye-media-stack.git
cd brother-eye-media-stack

# Copy the key file to the new machine (secure transfer)
# Then unlock with the key file
git-crypt unlock ~/brother-eye-gitcrypt.key

# Verify
cat secrets/test.env
```

---

## 🔍 Useful git-crypt Commands

```bash
# Check encryption status of files
git-crypt status

# Show which files are encrypted
git-crypt status -e

# Lock repository (encrypt all tracked files)
git-crypt lock

# Unlock repository
git-crypt unlock

# Add another GPG user
git-crypt add-gpg-user OTHER_GPG_KEY_ID

# Export symmetric key for backup/sharing
git-crypt export-key /path/to/backup.key
```

---

## 🛡️ Security Best Practices

### ✅ DO:
- **Use a strong GPG passphrase** (12+ characters, mixed case, numbers, symbols)
- **Backup your GPG keys** to multiple secure locations
- **Test unlock on another machine** before relying on encryption
- **Verify files are encrypted** with `git-crypt status`
- **Keep git-crypt.key file secure** if using symmetric key method
- **Use password manager** to store GPG passphrase and key backups

### ❌ DON'T:
- **Don't commit unencrypted secrets** (always verify with `git-crypt status`)
- **Don't share your private GPG key** insecurely
- **Don't lose your GPG passphrase** (you'll lose access to encrypted files)
- **Don't store GPG backups in plaintext** on cloud storage
- **Don't skip testing** the unlock process

---

## 🔧 Troubleshooting

### Problem: "git-crypt: command not found"

```bash
# Install git-crypt
apt update && apt install -y git-crypt
```

### Problem: "gpg: decryption failed: No secret key"

Your private key isn't imported. Import it:
```bash
gpg --import ~/brother-eye-gpg-private.asc
```

### Problem: "git-crypt unlock" does nothing / files still encrypted

```bash
# Check if you're unlocked
git-crypt status

# Force unlock
git-crypt unlock -f

# If using key file
git-crypt unlock /path/to/key/file
```

### Problem: Files not being encrypted

Verify `.gitattributes` is correct and committed:
```bash
cat .gitattributes
git add .gitattributes
git commit -m "Fix .gitattributes"
```

### Problem: Lost GPG passphrase

**Unfortunately, there's no recovery.** This is why backups are critical:
- If you have the exported private key but forgot passphrase: No recovery
- If you exported a symmetric key file: Use that instead
- **Prevention:** Store passphrase in password manager

### Problem: "error: gpg failed to sign the data"

Your GPG agent isn't running or key is locked:
```bash
# Restart GPG agent
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent

# Test signing
echo "test" | gpg --clearsign
```

---

## 📚 Alternative: Symmetric Key File (Simpler Setup)

If you don't want to deal with GPG keys, use a symmetric key file:

### Initial Setup:
```bash
cd /root/brother-eye-media-stack

# Initialize git-crypt without GPG
git-crypt init

# Export the key
git-crypt export-key ~/brother-eye-gitcrypt.key

# Store this key file securely (password manager, encrypted USB)
```

### On Another Machine:
```bash
# Clone and unlock
git clone git@github.com:YOUR_USERNAME/brother-eye-media-stack.git
cd brother-eye-media-stack
git-crypt unlock ~/brother-eye-gitcrypt.key
```

**Pros:**
- Simpler (no GPG required)
- One key file to manage

**Cons:**
- Less secure than GPG
- Must share the same key file with all users
- No per-user access control

---

## ✅ Verification Checklist

Before you rely on git-crypt, verify:

- [ ] GPG key generated with 4096-bit RSA
- [ ] GPG keys backed up to secure location
- [ ] GPG passphrase stored in password manager
- [ ] git-crypt initialized in repository
- [ ] `.gitattributes` committed and correct
- [ ] Test file encrypted successfully
- [ ] `git-crypt status` shows encrypted files correctly
- [ ] `git-crypt lock` encrypts files on disk
- [ ] `git-crypt unlock` decrypts files
- [ ] Tested clone and unlock on another machine (or documented how)

---

## 📖 Additional Resources

- [git-crypt GitHub](https://github.com/AGWA/git-crypt)
- [GPG Guide](https://www.gnupg.org/gph/en/manual.html)
- [Git Attributes Documentation](https://git-scm.com/docs/gitattributes)

---

**Next:** After completing this setup, you can safely commit sensitive files to the repository. They'll be encrypted automatically!
