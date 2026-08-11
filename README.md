<div align="center">

# 🐧 DuskyArch — aarch64 Edition

**A labor of love: 8+ months of tinkering, breaking, fixing, and polishing — ported to ARM.**
Designed to feel as easy to install as a "standard" distribution, but with the raw power
and minimalism of Arch.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Target](https://img.shields.io/badge/Arch-aarch64%20%2F%20ARM64-red.svg)](https://archlinuxarm.org)
[![Shell](https://img.shields.io/badge/Shell-Bash%20%2B%20Python-yellow.svg)](user_scripts/arch_setup_scripts)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/Zer0x-dev0/DuskyArch/pulls)

Please consider **starring ⭐** this repo as a token of support!

</div>

---

> [!WARNING]
>
> ## ⚠️ THIS EDITION IS FOR **aarch64 (ARM64) ONLY** — NOT x86_64
>
> This repository is the **ARM port** of the Dusky dotfiles. It is built for, tested on,
> and only supported on **Arch Linux ARM (aarch64)** machines — e.g. Apple Silicon
> (M1/M2/M3/M4) VMs, Raspberry Pi 4/5, Snapdragon laptops, or any ARM64 UEFI box.
>
> **It will NOT install correctly on x86_64 (Intel/AMD) hardware.** If you have an
> x86_64 machine, use the original project instead:
> 👉 [github.com/dusklinux/dusky](https://github.com/dusklinux/dusky)
>
> Everything in the install pipeline (pacman config, package lists, GPU setup, Spotify,
> Hyprland tweaks) has been adapted for aarch64. Details in the
> [Architecture section](#-architecture).

---

## 📑 Table of Contents

- [What is this?](#-what-is-this)
- [Architecture](#-architecture)
- [Prerequisites & Hardware](#-prerequisites--hardware)
- [Installation](#-installation)
- [Usage & Keybinds](#-usage--keybinds)
- [Features & Overview](#-features--overview)
- [Troubleshooting](#-troubleshooting)
- [Community & Media](#-community--media)
- [Contributing](#-contributing)
- [Acknowledgments](#-acknowledgments)
- [License](#-license)

---

## ✨ What is this?

A complete, polished Hyprland dotfiles setup for ARM — wallpapers, theming, a system
control center, and a host of terminal utilities — delivered through a smart installer
that handles everything for you.

### 🎛️ Dusky Control Center

There's a brand new Dusky Control Center that acts as a system overview GUI for settings
and features. It's exhaustive in its scope — almost anything you want to set or change
can be done from this one-stop-shop intuitive GUI app. More quality-of-life features are
added over time.

![Dusky Control Center](Pictures/readme_assets/dusky_control_center.webp)

### 🎨 Theming & Acknowledgments

A massive shoutout to [@Ubaidullah-Web-Dev](https://github.com/Ubaidullah-Web-Dev) for
his amazing project that enables website theming on gecko-based browsers like Firefox!
This configuration wouldn't have been possible without him.

⭐ **Support the Developer:** If you like the look of this setup, head over and drop a
star on his repository:
👉 [MatugenFox on GitHub](https://github.com/Ubaidullah-Web-Dev/MatugenFox)

---

## 🏗️ Architecture

**Target:** `aarch64` / `arm64` — **Arch Linux ARM** (ALARM).

**Verified on:** Apple M1 VM (virtio-gpu / virgl renderer), Hyprland 0.56+.

**Not supported:** x86_64, i686, riscv64. Use the original x86_64 project linked above.

### What was changed for aarch64 (vs the original x86_64 edition)

| Area | x86_64 original | This aarch64 edition |
|---|---|---|
| Pacman | `Architecture = auto`, multilib enabled | `Architecture = aarch64`, no multilib (multilib is x86-only) |
| Mirrors | `reflector` optimization | Skipped (uses official Arch Linux ARM mirrors) |
| Packages | Intel/AMD-only packages included | 9 x86_64-only packages removed: `intel-media-driver`, `vpl-gpu-rt`, `intel-gpu-tools`, `acpi_call`, `reflector`, `thermald`, `hwinfo`, `nvtop`, `shellcheck` |
| Spotify | Official Spotify client + SpotX ad-block | Official client and `spotube-bin` ship x86_64-only → **Spotube** installed from official **aarch64** builds (no Premium needed, ad-free) |
| Hyprland rendering | Standard GPU paths | `debug:damage_tracking = 0` — fixes half-rendered/cut tiled windows on virgl (common on virtio/ARM GPUs) |
| GPU detection | Intel/NVIDIA/AMD scripts | Auto-detects ARM GPUs (virtio, V3D, mali, etc.), skips x86-only GPU scripts |
| Theming engine | Single scheme from wallpaper | All **9 matugen scheme profiles** extracted per wallpaper + instant `theme_ctl profile` switching |
| Firefox theming | Static | **MatugenFox** — live theme sync from the active wallpaper scheme |

### 🛡️ NVIDIA / Intel-only features

Some original features are x86-only and intentionally skipped/adapted on ARM:

- NVIDIA GPU passthrough (Looking Glass) guide — NVIDIA x86-only.
- `Parakeet` STT model (NVIDIA) — use `Whisper` (CPU) on ARM instead.
- Intel `acpi_call` / battery quirks — ARM machines use their own ACPI handling.

---

## ⚠️ Prerequisites & Hardware

### Filesystem

This setup is optimized for the **BTRFS file system format**, but **works on ext4** as
well — the installer auto-detects your filesystem and skips btrfs-only features.

- **BTRFS:** ZSTD compression, copy-on-write (CoW) to prevent data corruption, and
  instant snapshots (snapper).
- **ext4:** Fully supported — the orchestra simply skips snapshot and
  compression-related steps (they're gated behind a filesystem check).

### Hardware Config (aarch64 / ARM64)

The setup scripts auto-detect your ARM hardware and set the appropriate environment
variables, but if your hardware is not detected or has some issues, you're advised to
configure the following files to set your environment variables.

> [!NOTE]
>
> Configure the uwsm env files to set your GPU environment variables.
>
> 1. Open the files at `~/.config/uwsm/env` and `~/.config/uwsm/env-hyprland`
>
> 2. Replace the GPU-specific variables with your hardware equivalents
>    (e.g. virtio-gpu on VMs, V3D on Raspberry Pi, etc.).

### Dual Booting

- Compatible with Windows (ARM) or other Linux distros.

- **Bootloader:** Defaults to `systemd-boot` for UEFI (boots up to 5s faster).
  Defaults to `GRUB` for BIOS.

---

## 💿 Installation

[Watch Video Tutorial](https://youtu.be/OzeFAY_8T8Y)

**Best for:** Users who already have a fresh, unconfigured **Arch Linux ARM (aarch64)**
installation with Hyprland. On Apple Silicon VMs (UTM/VMware/QEMU), install Arch Linux
ARM with the `generic-efi` or `uefi` kernel, pick **Btrfs** as the filesystem and
**Hyprland** as the window manager. On physical boards (Raspberry Pi 4/5, Snapdragon),
use the standard ALARM image.

> [!WARNING]
>
> The original **Dusky ISO is x86_64-only** and will NOT boot on ARM machines.
> For aarch64, start from a standard Arch Linux ARM install and use this repo's installer.

### Step 1: Clone Dotfiles (Bare Repo Method)

This uses a bare git repository method to drop files exactly where they belong in your
home directory. Make sure you're connected to the internet and git is installed:

```bash
sudo pacman -Syu --needed git
```

Clone the repo:

```bash
git clone --bare --depth 1 https://github.com/Zer0x-dev0/DuskyArch.git $HOME/dusky
```

Deploy the files on your system:

```bash
git --git-dir=$HOME/dusky/ --work-tree=$HOME checkout -f
```

> [!NOTE]
>
> This will immediately list a few errors at the top, but don't worry — that's expected
> behavior. The errors will later go away on their own after matugen generates colors
> and cycles through a wallpaper.

### Step 2: Run the Orchestra

Run the master script to install dependencies, themes, and services. This will take a
while because it sets up everything. You'll be prompted to say yes/no during setup, so
don't leave it running unattended.

```bash
python3 ~/user_scripts/arch_setup_scripts/orchestrator.py --profile 01_main
```

> [!NOTE]
>
> This fork's aarch64 patches (pacman, packages, spotify/spotube, etc.) live inside the
> scripts, so the orchestra applies them automatically. If you re-run it, keep the git
> self-update from wiping local state: add `--no-git-update` to the command above.

### The Orchestra Script

The `orchestrator.py` is a "conductor" that manages ~80 subscripts.

- **Smart:** It detects installed packages and skips them.

- **Safe:** You can re-run it as many times as you like without breaking things.

- **Time:** Expect 30–60 minutes. We use `paru` to install a few AUR packages, and
  compiling from source takes time. Grab a coffee! (ARM builds take a bit longer.)

---

## ⌨️ Usage & Keybinds

The steepest learning curve will be the keybinds. They're designed to be intuitive, but
feel free to change them in the config.

> 💡 **Pro Tip:**
>
> Press `CTRL + SHIFT + SPACE` to open the Keybinds Cheatsheet. You can click commands
> in this menu to run them directly!

It's been tested to work on other Arch-based distros with Hyprland installed (fresh
install) like CatchyOS.

---

## 🧰 Features & Overview

> [!NOTE]
>
> I've purposely decided to not use Quickshell for anything in the interest of keeping
> this as lightweight as possible — Quickshell can quickly add to RAM and slow down your
> system. Therefore everything is a user-friendly TUI to keep it snappy and lightweight
> while delivering on a whole host of features. Read below for most features.

### Utilities

- **Music Recognition** — look up what music is playing.
- **Circle-to-Search** — Google Lens-style feature.
- **Appearance TUI** — chain your Hyprland appearance (gaps, shadow color, blur
  strength, opacity, and a lot more!).
- **Local AI LLM** — Ollama sidebar (terminal-based, incredibly resource-efficient).
- **Keybind TUI Setter** — auto-checks for conflicts and unbinds any existing keybind in
  the default hyprland `keybind.conf`.
- **Swaync Side Toggle** — easily switch Swaync's side to left or right.
- **Airmon WiFi Script** — for WiFi testing/password cracking (only use on access points
  you own; the author is not legally responsible if used for nefarious purposes).
- **Live Disk I/O Monitoring** — see live read/write speeds during copying and infer if
  copying has actually finished. Useful for flash/external drives.
- **Quick Audio Switch** — switch audio input/output with a keybind (e.g. bluetooth
  headphones ↔ speakers without disconnecting).
- **Mono/Stereo Toggle** — audio toggling.
- **Touchpad Gestures** — volume/brightness, locking the screen, invoking swaync,
  pause/play, muting (requires a laptop or touchpad).
- **Battery Notifier** — for laptops; customize notification levels.
- **Power Saver Mode** — toggleable.
- **System Cleanup** — cache purge to reclaim storage.
- **USB Sounds** — notified when USB devices are plugged/unplugged.
- **FTP Server** — auto setup.
- **Tailscale** — auto setup.
- **OpenSSH** — auto setup, with or without Tailscale.
- **Warp (Cloudflare)** — auto setup and toggleable right from rofi.
- **VNC Setup** — for iPhones (wired).
- **Dynamic Fractional Scaling** — scale your display with a keybind.
- **One-Key Toggles** — toggle window transparency, blur, and shadow with a single
  keybind.
- **Hypridle TUI** — configuration.
- **WiFi Connector** — `~/user_scripts/network_manager/nmcli_wifi.sh`.
- **Sysbench Benchmark** — script.
- **Color Picker**.
- **Neovim Configured** — use as-is, or install LazyVim or any other neovim rice later.
- **GitHub Repo Integration** — easily create your own repo to back up all files. Uses
  a bare repo so your existing files listed in `~/.git_dusky_list` back up to GitHub;
  add/remove files from this text file.
- **BTRFS Compression Ratio** — scans your OS files to see how much space ZSTD
  compression saves you.
- **Drive Manager** — easily lock/unlock encrypted drives from the terminal ("unlock
  media" / "lock media"). Automatically mounts drives at a specified path and unmounts
  when locked. Requires configuring `~/user_scripts/drives/drive_manager.sh` with your
  drives' UUIDs.
- **NTFS Fix** — `ntfs_fix.sh`. NTFS drives tend to not unlock if the drive was
  disconnected without unmounting first (corrupted metadata); this script fixes it.

### Rofi Menus

- Emoji
- Calculator
- Matugen Theme Switcher
- Animation Switcher
- Power Menu
- Clipboard
- Wallpaper Selector
- Shader Menu
- System Menu

...and a lot more that would take forever to list — trust me, these dotfiles are the
shit! Try 'em out.

### GUI Sliders (keybind-invokable)

- Volume control
- Brightness control
- Nightlight / hyprsunset intensity

### Speech & Text

**Speech to Text:**
- Whisper — for CPU (recommended on ARM)
- Parakeet — for NVIDIA GPUs (might also work on AMD, not sure) — x86_64 NVIDIA only.

**Text to Speech:**
- Kokoro — for both CPU and GPU.

### Extras

- **Mechanical Keypress Sounds** — toggleable with a keybind or from rofi.
- **Wlogout** — drawn using a dynamic script that respects your fractional scaling.

### 🎨 Theming

- **Wallpaper-Powered Theming:** Matugen extracts all **9 color scheme profiles**
  (tonal-spot, vibrant, neutral, expressive, content, fidelity, fruit-salad,
  monochrome, rainbow) from your wallpaper, applied across the entire system.
- **Instant Profile Switching:** `theme_ctl profile next` swaps the active scheme in
  ~0.5s and re-applies it to every app (waybar, hyprland, kitty, mako, rofi, gtk/qt, ...).
- **Live Firefox Theming:** MatugenFox syncs the active wallpaper scheme into Firefox in
  real time — change the wallpaper and your browser recolors instantly, no reload.

### ⚡ Performance & System

- **Lightweight:** ~900MB RAM usage and ~5GB disk usage (fully configured).
- **ZSTD & ZRAM:** Compression enabled by default to save storage and triple your
  effective RAM (great for low-spec machines).
- **Native Optimization:** AUR helpers configured to build with CPU-native flags
  (up to 20% performance boost).
- **UWSM Environment:** Optimized specifically for Hyprland.

### 🖥️ Graphics

- **Fluid Animations:** Tuned physics and momentum for a "liquid" feel — days spent
  fine-tuning this.
- **Instant Shaders:** Switch visual shaders instantly via Rofi.
- **Android Support:** Automated Waydroid installer script.

### 🎯 Usability

- **Universal Theming:** Matugen powers a unified Light/Dark mode across the system.
- **Dual Workflow:** Designed for both GUI-centric (mouse) and terminal-centric
  (keyboard) users.
- **Accessibility:** Text-to-Speech (TTS) and Speech-to-Text (STT) capabilities
  (hardware dependent).
- **Keybind Cheatsheet:** Press `CTRL` + `SHIFT` + `?` anytime to see your controls.

### 🧭 Waybar

YES, you can have a **horizontal waybar**. You'll be asked which side you want it on
(bottom/top/left/right).

- **Waybar horizontal and vertical:** Take your pick during setup, easily toggleable
  from rofi as well. Here's what it looks like:

![New Nerdy Horizontal Waybar](Pictures/readme_assets/waybar_horizontal.webp)

![Waybar Block](Pictures/readme_assets/waybar_block.webp)

![Waybar Circular](Pictures/readme_assets/waybar_circular.webp)

![Waybar Minimal](Pictures/readme_assets/waybar_minimal.webp)

---

## 🔧 Troubleshooting

If a script fails (which can happen on a rolling-release distro):

1. **Don't Panic.** The scripts are modular. The rest of the system usually installs
   fine.

2. **Check the Output.** Identify which subscript failed
   (located in `$HOME/user_scripts/arch_setup_scripts/scripts/`).

3. **Run Manually.** You can try running that specific subscript individually.

4. **AI Help.** Copy the script content and the error message into
   ChatGPT/Gemini. It can usually pinpoint the exact issue (missing dependency, changed
   package name, etc.).

---

## 🌐 Community & Media

- 🎬 **Demo video on YouTube** — covers all major features (since the release of this
  video around 5 major features have been added, scroll up to the
  [overview section](#-features--overview) for details):
  [Watch now](https://youtu.be/JmgvSdEIK8c)

- 💬 **Community Discord** — the official Discord server has been deleted, but a
  community server has been created. Please note the original developer is not involved
  with this community server in any capacity. You can also participate on the
  [Discussions page](https://github.com/Zer0x-dev0/DuskyArch/discussions).
  [Join Community Discord Server](https://discord.gg/V2EeUJwd4)

- 🖼️ **Wallpapers** — all +1050 wallpapers are available from the
  [images repo](https://github.com/dusklinux/images).

---

## 🤝 Contributing

Contributions are welcome! Feel free to open an issue for bugs or feature requests, or
submit a pull request. Please keep in mind:

- This is an **aarch64-only** port — changes targeting x86_64 belong in the original
  project.
- Test changes against an ARM machine/VM before submitting.
- Keep scripts modular and re-runnable (the orchestra is meant to be safe to re-run).

---

## 🙏 Acknowledgments

Thank you to all the contributors!

SDDM is a modified version of the SilentSDDM project by
[@uiriansan](https://github.com/uiriansan) (a great project — kindly star it on
GitHub): [SilentSDDM](https://github.com/uiriansan/SilentSDDM)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

<div align="center">

Enjoy the experience! 🎉

If you run into issues, check the detailed Obsidian notes included in the repo (~2MB).

</div>
