#!/usr/bin/env python3

# A simple script to build 64-bit and 32-bit Mesa and libdrm on amd64 Debian
# stable, Debian testing, Debian unstable, and possibly some Ubuntu versions
# with some tweaks.
#
# libdrm is build too, because often version right now in Debian sid and experimental
# is too old for current mesa git repo. Also it is nice to build debug
# versions of libdrm when troubleshooting some crashes and bugs.
#
# A situation with LLVM on Ubuntu was (is?) not perfect, so you are on your own.
#
# If you do not want to or can not use it, modify the script to install and use
# other LLVM and update LLVMVERSION variable below.
#
# It is too complex to handle fully automatically and be future proof. So just
# edit the script accordingly.
#
# By default only drivers for AMD, Intel and software rendering will be built.
# That will build radeon driver, radv (with ACO and LLVM), llvmpipe,
# lavapipe, and zink, with few other minor things.
#
# No Nvidia drivers will be compiled. This is to speed up compilation
# a bit, but also due to sporadic compile issues.
# Modify MESA_COMMON_OPTS or check --gallium-drivers and --vulkan-drivers
# flags to enable it that.
#
# OpenCL support with rusticl will be built for 64-bit only.
#
# Valgrind extra support will be built for 64-bit only too.
#
# Otherwise rest (Mesa, OpenGL, Vulkan, Mesa overlay layer, Mesa device selection
# layer, zink, lavapipe), will be built for both 64-bit and 32-bit versions.
#
# OpenGL ES (GLES) and EGL are also built. Previously it was disabled, as
# I found not use for it, beyond making compilation slower, but as of 2022,
# few critical apps require it in some configurations.
#
# Use --buildopt=1 to enable also debug builds, which can build
# together with optimized builds.
#
# The build will be performed in ~/mesa-git directory for you.
#
# The source tree will live in ~/mesa-git
# Built libraries and binaries will be in ~/mesa-git/builddir/build-{amd64,i386}-{dbg,opt}/
# Libraries and binaries will be installed into ~/mesa-git/installdir/build-{amd64,i386}-{dbg,opt}/
#
# After compilation is done, the script will perform a small test with glxinfo,
# vulkaninfo and vkcube for 2 seconds.
#
#
# After compilation is done, use '. ~/enable-new-mesa-opt.source'
# (without quotes) in your terminal to enable it.
# You can add it to your ~/.profile or ~/.bashrc file too.
#
# You need to use this '. ~/enable-new-mesa-opt.source' before any other
# OpenGL / Vulkan app is started from the same terminal. It is not enough to
# simply do '. ~/enable-new-mesa-opt.source' in a terminal, and the launch
# steam or some game via desktop shorcut, or other terminal. The changes are
# local to the terminal / shell you used it to. You can use it in many terminals
# as you wish.
#
# Note that `enable-new-mesa-opt.source` will also automatically enable ACO if
# available and enable Vulkan Mesa overlay, Gallium HUD, and DXVK HUD.
# Feel free to modify this script below (line ~280 and ~328) to not do that.
# Or source the `disable-new-mesa-hud.source` script to undo the HUD stuff.
#
# Alternatively use ~/mesa-opt shell wrapper to prepend to your commands,
# i.e. Steam, ~/mesa-opt mangohud %command% for example.
#
# Similarly zink variants will enable use of Zink for OpenGL using Vulkan.
#
# This script will not install libraries system wide, so it is safe to use in
# parallel with your distro libraries. And even have applications using one
# or another, or some using optimized libraries and some using debug libraries.
#
# To get rid of it simply run:
#
# rm -rf ~/mesa-git ~/libdrm-git ~/enable-new-mesa-*.source ~/disable-new-mesa-hud.source ~/{mesa,zink}-{opt,dbg}
#
# If you want to use this Mesa's OpenGL / Vulkan for your desktop manager, like
# Gnome Shell, you are on your own, but it can be probably done some way by
# putting needed variables in /etc/environment. Maybe...
# Or tweak INSTALLDIR variable. But few more variables (`-Dprefix` for example)
# will be needed to be changed. See https://www.mesa3d.org/meson.html for details.
#
# By default rerunning this script will reuse builddir and installdirs,
# and perform incremental build. But it will not fetch new version.
#
# To fetch new version of mesa and drm, pass --git-pull=1
#
# To do rebuild from scratch. Pass --incremental=0
#
# Alternatively, you can do "git pull", then go into proper
# build subdirectory and recompile, i.e. using:
#
#  cd ~/mesa-git/builddir/build-amd64-opt/ && ninja && ninja install
#
# Copyright: Witold Baryluk <witold.baryluk@gmail.com>, 2019-2024
# License: MIT style license
# Also thanks for bug reports, contributions and fixes, including, from:
#   @serhii-nakon, @kofredwan13, @gremble

import argparse
import os
import shutil
import subprocess
import sys
import time


assert os.getuid() != 0, "Do not run this script under root or using sudo!"

HOME = os.environ["HOME"]
assert HOME and not HOME.endswith("/")

os.chdir(HOME)

PWD = os.getcwd()

SOURCEDIR_LIBDRM = f"{HOME}/libdrm-git"
SOURCEDIR_MESA = f"{HOME}/mesa-git"

BUILDDIR = f"{PWD}/mesa-git/builddir"
# Aka prefix, but we put each build into separate subprefix.
# So in total there will be 4 subprefixes (64-bit optimized, 32-bit optimized,
# 64-bit debug, 32-bit debug)
INSTALLDIR = f"{PWD}/mesa-git/installdir"

USE_SYSTEM_LIBDRM = False  # Set to True to use system libdrm-dev.

def str2bool(x) -> bool:
    if x.lower() in {"true", "t", "yes", "y", "1"}:
        return True
    if x.lower() in {"false", "f", "no", "n", "0"}:
        return False
    raise Exception("boolean flags can only be true, True, t, yes, y, Y, 1, false, False, f, no, n, N, 0, etc")

parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
# Show less output, but also do fully automatic apt-get setup not needing any confirmations.
parser.add_argument("--quiet", help="Run in quiet and automated mode", default=False, type=str2bool)
parser.add_argument("--debug", help="Run in debug mode", default=False, type=str2bool)
parser.add_argument("--apt-auto", help="Automatically install required dependencies. If 0, also skip some verifications.", default=True, type=str2bool)
parser.add_argument("--llvm", help="Select LLVM / libclc / libclang version to use. auto - try to autodetect.", default="auto")
parser.add_argument("--git-repo-mesa", help="If sourcedir doesn't exist, clone the repo with URL.", default="https://gitlab.freedesktop.org/mesa/mesa.git")
parser.add_argument("--git-branch-mesa", help="For --git-repo-mesa which branch to checkout.", default="")
parser.add_argument("--git-repo-libdrm", help="If sourcedir doesn't exist, clone the repo with URL.", default="https://gitlab.freedesktop.org/mesa/drm.git")
parser.add_argument("--git-branch-libdrm", help="For --git-repo-libdrm which branch to checkout.", default="main")
parser.add_argument("--git-depth", help="For --git-repo-mesa and --git-repo-libdrm what --depth=N to use.", default=1)
#parser.add_argument("--git-full-depth", help="For the clone, use full clone, instead of using --depth=1000.", default=False, type=str2bool)
parser.add_argument("--git-pull", help="Do a git pull for libdrm and mesa in existing git clones, before build.", default=False, type=str2bool)
#parser.add_argument("--no-clean", help="Don't remove builddir and installdir at the start.", default=False, type=str2bool)
parser.add_argument("--incremental", help="Don't remove builddir and installdir at the start, but invoke compile and install again.", default=True, type=str2bool)
#parser.add_argument("--sourcedir", help="Where to put mesa sources.", default=f"{HOME}/mesa-git")
#parser.add_argument("--builddir", help="Base for the build location.", default=BUILDDIR)
#parser.add_argument("--installdir", help="Base for the install location.", default=INSTALLDIR)
parser.add_argument("--build64", help="Build 64-bit version.", default=True, type=str2bool)
parser.add_argument("--build32", help="Build 32-bit version.", default=True, type=str2bool)

# Build optimized (-march=native -O2) binaries. If not, only separate debug
# build is built.
parser.add_argument("--buildopt", help="Build optimized (-O2 -march=native + debug code disabled) version. (can be enabled with --builddebug, two builds will be created)", default=True, type=str2bool)

# Build separate debug builds with -O1 -ggdb and Mesa debugging code (extra
# runtime checks and asserts) present. You can have both BUILDOPT and
# BUILDDEBUG enabled, and two versions of Mesa will be built, and you can
# switch between them per-app quickly. It is not recommended to use it in
# general unless you find an issue in some apps, crashes, or glitches.
# It is safe to enable building debug builds, even if you are only going to
# use optimized built. They are completly independent.
parser.add_argument("--builddebug", help="Build debug (-O1 -ggdb -g3 + asserts / checks enabled) version. (can be enabled with --buildopt, two builds will be created)", default=False, type=str2bool)

# Use heavy optimizations (-march=native -O3 -free-vectorize -flto -g0) in
# optimized build. This will take about twice as long to compile, might
# expose extra bugs in Mesa or GCC, and will make debugging a bit harder.
# I personally didn't notice any significant performance improvements,
# but in theory they are slightly faster.
parser.add_argument("--heavyopt", help="Use additionally -O3 -march=native -flto -g -mf16c -mfpmath=sse ... et al for --buildopt.", default=False, type=str2bool)

# Build OpenCL support for 64-bit. This flag is ignored
# for 32-bit builds at the moment, but in future it will be used there too.
parser.add_argument("--buildopencl", help="Include OpenCL support", default=True, type=str2bool)

#parser.add_argument("--buildextras", help="Build extras (i.e. fossilize, shader-db).", default=True, type=str2bool)

parser.add_argument("--gallium-drivers", help="Drivers to include.", default="radeonsi,r600,zink,virgl,softpipe,llvmpipe")
# r600 disabled, because it requires LLVM, but we now try to build without LLVM by default  (meson.build:1765:4: ERROR: Problem encountered: R600 requires LLVM AMD support.)
# 2024-02-13: Removed iris,crocus,i915 because of complex compilation issues related to meson native: true, intel_clc on amd64

parser.add_argument("--vulkan-drivers", help="Drivers to include.", default="amd,swrast,virtio")
# noveau disabled, because (and also because I do not use it) of some bindgen issues: Unable to generate bindings: ClangDiagnostic("/home/user/mesa-git/src/nouveau/winsys/./nouveau_bo.h:41:4: error: unknown type name 'atomic_uint_fast32_t'\n")
# Note: intel,intel_hasvk,  # disabled due to issues with intel_clc on amd64
# gfxstream-experimental not enabled because: src/gfxstream/guest/meson.build:30:16: ERROR: Dependency "aemu_base" not found, tried pkgconfig

def ignore_flag(x):
    print("Warning: --wayland flag is enabled unconditionally, and will be removed in the future", file=sys.stderr)
    print("Build will continue in 10 seconds", file=sys.stderr)
    time.sleep(10)
    return True
parser.add_argument("--wayland", help="This flag is ignored, and will be removed in late 2025", default=True, type=ignore_flag)

# parser.add_argument("--endchecks", help="Perform post-install tests / sanity checks.", default=True, type=str2bool)
# parser.add_argument("--uninstall", help="Cleanup everything, sourcedir, builddir, installdir, and generated files, and exit. (Remember to pass --*dir options first, if needed).", default=False, type=str2bool)


args = parser.parse_args()

assert len(set([HOME, SOURCEDIR_MESA, SOURCEDIR_LIBDRM, BUILDDIR, INSTALLDIR])) == 5, "All used directories must be unique"


def maybeprint(*print_args):
    if not args.quiet:
        print(*print_args)

        
def run(cmd_args, *, env = None, check: bool = True) -> bool:
    print("Running", *cmd_args)
    try:
        if args.quiet:
            p = subprocess.run(cmd_args, stdout=subprocess.DEVNULL, env=env)
        else:
            p = subprocess.run(cmd_args, env=env)
    except FileNotFoundError:
        print("Command failed:", *cmd_args)
        # I.e. sudo or lsb_release missing
        print("Maybe", cmd_args[0], "is not installed?")
        if check:
            sys.exit(1)
    if check:
        if p.returncode != 0:
            print("Command failed:", *cmd_args)
            print("with exit code:", p.returncode)
            sys.exit(1)
        # p.check_returncode()  # Throws exception, with not too pretty trace
    return p.returncode == 0


def capture(cmd_args, *, env = None) -> bool:
    p = subprocess.run(cmd_args, stdout=subprocess.PIPE, universal_newlines=True, env=env)
    return p.stdout


def grep(cmd_stdout: str, pattern: str) -> list[str]:
    assert isinstance(pattern, str)
    return [line.rstrip() for line in cmd_stdout.splitlines() if line.startswith(pattern)]


# Run CPU intensive parts at low priority so they can run in background,
# with less interference to other apps.
NICE = ["nice", "--adjustment=20"]

assert args.buildopt or args.builddebug, "At least one of the --buildopt and --builddbg is required"
assert args.build32 or args.build64,  "At least one of the --build32 and --build64 is required"

if args.build32:
    print("Checking multiarch support ...")
    maybeprint()
    p = capture(["dpkg", "--print-foreign-architectures"])
    if "i386" not in p.splitlines():
        print("No multiarch enabled. Please run (as root) below command:")
        print()
        print("dpkg --add-architecture i386 && apt-get update")
        print()
        print("and then retry this script again.")
        print()
        print("Alternatively run this script with --build32=false option to disable building i386 (32-bit) mesa")
        sys.exit(2)


APT_INSTALL = [
    "apt-get",
    "install",
    "--option", "APT::Get::HideAutoRemove=1",
    "--option", "quiet::NoProgress=1",
    "--no-install-recommends",
]

if args.quiet:
    APT_INSTALL.extend(["-qq", "--assume-yes", "--no-remove", "--option","Dpkg::Use-Pty=0"])

SUDO = ["sudo", "--preserve-env=DEBIAN_FRONTEND,APT_LISTCHANGES_FRONTEND,NEEDRESTART_MODE,NEEDRESTART_SUSPEND,DEBIAN_FRONT"]

new_env = dict(os.environ)
new_env.update({
    "DEBIAN_FRONTEND": "noninteractive",
    "APT_LISTCHANGES_FRONTEND": "none",
    "NEEDRESTART_MODE": "l",  # list only
    "NEEDRESTART_SUSPEND": "1",  # do not run at all temporarily from apt-get
    "DEBIAN_FRONT": "noninteractive",  # for needrestart, just in case.
})


def sudo(cmd_args, check: bool = True):
    return run(SUDO + cmd_args, env=new_env, check=check)


def maybenewline():
    if not args.quiet:
        print()


if args.apt_auto and args.build32:
    maybeprint()
    print("Checking base dependency versions on amd64 and i386 ...")
    maybeprint()

    sudo(APT_INSTALL + ["libc6-dev:amd64", "libc6-dev:i386"])

    # Sometimes some packages might reach only one architecture first, and it might
    # be really hard to coinstall some package on both amd64 and i386, when they are
    # out of sync. Check they are in sync first.
    # Note: This can be done nicer using dctrl-tools package, but it is not
    # installed by default or needed.
    v1 = grep(capture(["dpkg", "-s", "linux-libc-dev:amd64"]), "Version")
    v2 = grep(capture(["dpkg", "-s", "linux-libc-dev:i386"]), "Version")
    if v1 != v2:
        print("linux-libc-dev:amd64 and linux-libc-dev:i386 do have different versions!")
        print("Please fix first and then retry.")
        sys.exit(2)
    v1 = grep(capture(["dpkg", "-s", "libc6-dev:amd64"]), "Version")
    v2 = grep(capture(["dpkg", "-s", "libc6-dev:i386"]), "Version")
    if v1 != v2:
        print("libc6-dev:amd64 and libc6-dev:i386 do have different versions!")
        print("Please fix first and then retry.")
        sys.exit(2)
else:
    maybeprint()
    print("Checking base dependency versions on amd64 ...")
    maybeprint()

    sudo(APT_INSTALL + ["libc6-dev:amd64"])

try:
    LSB_DIST = capture(["lsb_release", "-is"]).strip()
except FileNotFoundError as e:
    print("Command failed:", "lsb_release", "-is", file=sys.stderr)
    print("Error:", e, file=sys.stderr)
    # TODO(baryluk): We can bypass lsb_release and read /etc/debian_version maybe
    print("Maybe package lsb-release is not installed?")
    sys.exit(1)
LSB_VERSION = capture(["lsb_release", "-sr"]).strip()
DIST_VERSION = LSB_DIST + "_" + LSB_VERSION

LLVMVERSION = "19"
GCCVERSION = "15"

LLVMREPO = []

LIBCLC_PACKAGES = ["libclc-dev"]

# Not installing libclc-14-dev will uninstall mesa-opencl-icd, and install pocl-opencl-icd
# This is suboptimal, but should still work, and OpenCL is not a big thing anyway.

if DIST_VERSION.startswith("kali-rolling"):    LLVMVERSION=19;     GCCVERSION=15; LIBCLC_PACKAGES=["libclc-19-dev"]  # Kali
elif DIST_VERSION.startswith("Kali_2025.3"): LLVMVERSION=19;    GCCVERSION=15; LIBCLC_PACKAGES=["libclc-19-dev"] # Forky / kali
elif DIST_VERSION == "Debian_testing":     LLVMVERSION=19;    GCCVERSION=15; LIBCLC_PACKAGES=["libclc-19-dev"] # currrently Forky

else:
    print(f"Warning: Distribution '{DIST_VERSION}' is not supported by this script")
    LLVMVERSION = 19
    GCCVERSION = 15

if args.llvm != "auto":
    LLVMVERSION = args.llvm
    LIBCLC_PACKAGES = [f"libclc-{args.llvm}-dev"]

LLVMVERSION = str(LLVMVERSION)

# Main Mesa dependencies which we will install both on amd64 and i386
#
# wayland-protocols is :all, and dpkg will install no issues.
# But bison, flex, pkg-config, glslang-tools we only want amd64 for build.
#
# We keep the order in the list same as Meson configure output.
MAINDEPS = [
    # "linux-libc-dev",  # Probably will be pulled by gcc & co.
    # linux-libc-dev is not libc-dev. It has Linux kernel headers,
    # for use by userspace, 'uapi'.

    "libvulkan-dev",
    # "glslang-tools",  # We only want to install amd64 binary version.

    "libxv-dev",
    "libva-dev",
    "zlib1g-dev",
    "libzstd-dev",
    "libexpat1-dev",

    # "libdrm-dev",  # We build our own by default now.

    # LLVM stuff

    "libelf-dev",
    "libglvnd-dev",
    # "libglvnd-core-dev",
    # "bison",  # We only want to install amd64 binary version.
    # "flex",  # We only want to install amd64 binary version.

    # "libunwind-dev",

    # pkg-config stuff  # We install it separately, because it is a bit more complex.

    # "libwayland-bin",  # For wayland-scanner. Technically dependency of libwayland-dev
                       # We only want to install amd64 binary version.

    "wayland-protocols",
    "libwayland-dev",
    "libwayland-egl-backend-dev",

    "libx11-dev",
    "libxext-dev",
    "libxfixes-dev",
    "libxcb-glx0-dev",
    "libxcb-shm0-dev",
    "libxcb1-dev",
    "libx11-xcb-dev",
    "libxcb-dri2-0-dev",
    "libxcb-dri3-dev",
    "libxcb-present-dev",
    "libxcb-sync-dev",
    "libxcb-keysyms1-dev",   # Optional, not sure what is this for, but maybe for GALLIUMHUD hotkeys?
    "libxshmfence-dev",
    "x11proto-dev",  # For glproto and dri2proto. Technically dependency of other libx* packages.
    "libxxf86vm-dev",
    "libxcb-xfixes0-dev",
    "libxcb-randr0-dev",
    "libxrandr-dev",

    # "libxdamage-dev",  # I do not see it Meson output, and I do not think is needed. Debian Build-Depends has it.
    "libxcb-sync-dev",  # I don't see it Meson output, but it is in Debian Build-Depends.

    "libsensors-dev",

    # libdrm dependencies from Debian.
    #
    # minus some that can be 64-bit,
    # minus valgrind, minus quilt (debian specific patching) and xsltproc (docs).
    # "meson", "quilt", "xsltproc",
    "libx11-dev",
    # "pkg-config",
    # "xutils-dev",  # X Window System utility programs for development # We can use 64-bit version for 32-bit.
    "libudev-dev",
    "libpciaccess-dev",
    # "python3-docutils",
    # "valgrind",

    "libcunit1-dev",  # Optional. For libdrm tests.

    "liblua5.4-dev",  # Optional. Used be Intel and Freedreno for some extra stuff.
]

if USE_SYSTEM_LIBDRM:
    MAINDEPS.extend(["libdrm-dev"])
else:
    MAINDEPS.extend(["libcairo-dev"])  # for some libdrm tests


MAINDEPS64 = []
MAINDEPS32 = []
for d in MAINDEPS:
    assert ":" not in d
    MAINDEPS64.append(f"{d}:amd64")
    if args.build32:
        MAINDEPS32.append(f"{d}:i386")

# For OpenCL support, one might need libclc-dev and libclang-XYZ-dev, to add a parser
# and some passes from LLVM. (See https://libclc.llvm.org for details). This is AFAIK
# for Clover subproject in Mesa, which is disabled, but might go forward, especially
# for Novoue driver, and possibly in the future as a SPIR-V target, which is then
# consumed by LLVM or by ACO, via NIR again.
OPENCL_DEPS = []
if args.buildopencl:
    OPENCL_DEPS = [f"libclang-{LLVMVERSION}-dev:amd64", f"libclang-cpp{LLVMVERSION}-dev"]
    OPENCL_DEPS.extend(LIBCLC_PACKAGES)
    # Polly is optional, but enables various optimisations of OpenCL kernels
    OPENCL_DEPS += [f"libpolly-{LLVMVERSION}-dev:amd64"]
    # if args.builds32:
    #   # https://bugs.debian.org/1055371
    #   OPENCL_DEPS.extend([f"libpolly-{LLVMVERSION}-dev:i386"])

if args.apt_auto:
    maybeprint()
    if USE_SYSTEM_LIBDRM:
        print("Ensuring dependencies for Mesa (and libdrm) build are installed ...")
    else:
        print("Ensuring dependencies for Mesa build are installed ...")
    maybeprint()

    ALL_PACKAGES = [
        "mesa-utils",  # for glxinfo
        "vulkan-tools",  # for vkcube
        "git",
        "ca-certificates", # for git, just in case, because it is only in Recommends, and is not in base system
        f"gcc-{GCCVERSION}",
        f"g++-{GCCVERSION}",
        # "gcc", "g++",  # for vkpipeline-db, otherwise cmake has issues.
        "pkg-config",
        "meson",
        "ninja-build",
        # "cmake",  # for vkpipeline-db
        "gettext",
        "python3",
        "python3-setuptools",
        "python3-mako",
        "valgrind",
        "bison",
        "flex",
        "dpkg-dev",  # is needed by multi-arch-aware pkg-config when cross-compiling
        "glslang-tools",
        *OPENCL_DEPS,
        "xutils-dev:amd64",  # for libdrm, but these are build utilities, only need amd64 version.

        "bindgen",  # rust ffi via C and C++. For building rusticl OpenCL stuff
        "cbindgen",  # Generates C bindings from Rust code  - used by src/nouveau/nil/

        "rustfmt",
        "librust-paste-dev",
        "librust-syn-dev",
    ]

    if args.build64:
        ALL_PACKAGES.extend([
            *MAINDEPS64,
        ])

    if args.build32:
        ALL_PACKAGES.extend([
            f"gcc-{GCCVERSION}-i686-linux-gnu",
            f"g++-{GCCVERSION}-i686-linux-gnu",
            *MAINDEPS32,
        ])

    if args.buildopencl:
        if LLVMVERSION == "11":
            if args.build64:
                ALL_PACKAGES.append("libllvmspirvlib-dev:amd64")
            if args.build32:
                ALL_PACKAGES.append("libllvmspirvlib-dev:i386")
        elif LLVMVERSION == "13":
            if args.build32:
                ALL_PACKAGES.append(f"libllvmspirvlib-{LLVMVERSION}-dev:amd64")
            # if args.build32:
            #     ALL_PACKAGES.append(f"libllvmspirvlib-{LLVMVERSION}-dev:i386")
        elif LLVMVERSION == "14":
            if args.build64:
                ALL_PACKAGES.append(f"libllvmspirvlib-{LLVMVERSION}-dev:amd64")
            if args.build32:
                if DIST_VERSION not in {"Ubuntu_22.04", "Linuxmint_21.1", "Pop_22.04"}:
                    ALL_PACKAGES.append(f"libllvmspirvlib-{LLVMVERSION}-dev:i386")
        else:
            if args.build64:
                ALL_PACKAGES.append(f"libllvmspirvlib-{LLVMVERSION}-dev:amd64")
                ALL_PACKAGES.append(f"llvm-spirv-{LLVMVERSION}:amd64")
            if args.build32:
                ALL_PACKAGES.append(f"libllvmspirvlib-{LLVMVERSION}-dev:i386")

    ALL_PACKAGES.extend([
        "wayland-protocols",
        "libwayland-bin",
    ])

    # Install directx-headers-dev for amd64 only for now.

    # Note: We need glslangValidator to compile trivial GLSL code into SPV for Vulkan Mesa overlay.
    # Compilers and cross compilers. Will automatically install binutils (for ar, strip, etc.).
    sudo(APT_INSTALL + ALL_PACKAGES)

# Allow installation of directx-headers-dev:amd64 to fail.
# It is now in testing (bookworm) and unstable, as of 2022-02-08.
# It is also in current stable (since release of bookworm, middle 2023).
# TODO: So maybe test with it included unconditionally.
if args.apt_auto:
    if not sudo(APT_INSTALL + ["directx-headers-dev:amd64"], check=False):
        print("Warning: Can not install directx-headers-dev:amd64. Consider switching to Debian unstable / Debian bookworm to get it.")

if not USE_SYSTEM_LIBDRM:
    # TODO(baryluk): Separate dependencies for libdrm. I.e. xutils-dev:amd64, and libpciaccess-dev, libudev-dev.
    pass

if args.apt_auto:
    maybeprint()
    maybeprint()
    print(f"Attempting to install llvm{LLVMVERSION} ... If it fails, please read the source code how to add proper repos...")
    maybeprint()
    maybeprint()
    LLVM_PACKAGES = [
        f"libllvm{LLVMVERSION}",
        f"libllvm{LLVMVERSION}:amd64",
        f"llvm-{LLVMVERSION}-dev",
    ]
    LLVM_PACKAGES_DBG=[
        f"libllvm{LLVMVERSION}-dbgsym:amd64",
    ]
    if args.build32:
        LLVM_PACKAGES += [
            f"libllvm{LLVMVERSION}:i386",
            # f"llvm-{LLVMVERSION}:i386",
        ]
        LLVM_PACKAGES_DBG += [
            f"libllvm{LLVMVERSION}-dbgsym:i386",
        ]

    sudo(APT_INSTALL + LLVMREPO + LLVM_PACKAGES)
    if not sudo(APT_INSTALL + LLVMREPO + LLVM_PACKAGES_DBG, check=False):
        print("Warning: Can't install debug symbols. Enable them: https://wiki.debian.org/HowToGetABacktrace")

# No need to install pkg-config:i386, it would conflict with pkg-config:amd64.
# Debian's pkg-config will automatically create symlinks to all supported
# archs to proper wrapper that sets proper paths.

# A 32-bit version of pkg-config, that actually is a wrapper, that knows how to
# filter various libraries and multiple versions of them.
# removes pkg-config:amd64, but kind of fine for a moment. We still can use the
# properly prefixed versions all the time!

GIT_QUIET_ARG = ["--quiet"] if args.quiet else []

if not USE_SYSTEM_LIBDRM:
    maybeprint()
    print("Checking libdrm git repo ...")
    maybeprint()

    if not os.path.exists(SOURCEDIR_LIBDRM):
        if args.git_depth != "":
            GIT_DEPTH_ARG = [f"--depth={args.git_depth}"]
        if args.git_branch_libdrm:
            GIT_BRANCH_ARG = [f"--branch={args.git_branch_libdrm}", "--single-branch"]
        else:
            GIT_BRANCH_ARG = []
        run([*NICE, "git", "clone", *GIT_QUIET_ARG, *GIT_DEPTH_ARG, *GIT_BRANCH_ARG, args.git_repo_libdrm, SOURCEDIR_LIBDRM])
        if args.git_branch_libdrm:
            run([*NICE, "git", "-C", SOURCEDIR_LIBDRM, "checkout", *GIT_QUIET_ARG, args.git_branch_libdrm])
    else:
        if args.git_pull:
            run([*NICE, "git", "-C", SOURCEDIR_LIBDRM, "pull", *GIT_QUIET_ARG])
        else:
            print(f"libdrm-git repo already present. To update, use --git-pull=1 option or run \"cd '{SOURCEDIR_LIBDRM}' && git pull\" manually.")
    maybeprint()


maybeprint()
print("Checking mesa git repo ...")
maybeprint()

if not os.path.exists(SOURCEDIR_MESA):
    if args.git_depth != "":
        GIT_DEPTH_ARG = [f"--depth={args.git_depth}"]
    if args.git_branch_mesa:
        GIT_BRANCH_ARG = [f"--branch={args.git_branch_mesa}", "--single-branch"]
    else:
        GIT_BRANCH_ARG = []
    run([*NICE, "git", "clone", *GIT_QUIET_ARG, *GIT_DEPTH_ARG, *GIT_BRANCH_ARG, args.git_repo_mesa, SOURCEDIR_MESA])
    if args.git_branch_mesa:
        run([*NICE, "git", "-C", SOURCEDIR_MESA, "checkout", *GIT_QUIET_ARG, args.git_branch_mesa])
else:
    if args.git_pull:
        run([*NICE, "git", "-C", SOURCEDIR_MESA, "pull", *GIT_QUIET_ARG])
    else:
        print(f"mesa-git repo already present. To update, use --git-pull=1 option or run \"cd '{SOURCEDIR_MESA}' && git pull\" manually.")

maybeprint()

# Required for parsing OpenCL is enabled.
# The clang-cpp component can be skipped, but helps with some stuff apparently.
if args.apt_auto:
    sudo(APT_INSTALL + [f"libclang-{LLVMVERSION}-dev", f"libclang-cpp{LLVMVERSION}-dev:amd64"])


os.chdir(SOURCEDIR_MESA)

# These are roots of the build and install.
# Actuall build and install will happen in various
# subdirectories, for mesa, libdrm, 32-bit & 64-bit, opt & dbg.

if not args.incremental:
    print()
    print(f"Cleaning previous build directory {BUILDDIR}")
    try:
        shutil.rmtree(BUILDDIR)
    except FileNotFoundError:
        pass
    print()
    print(f"Cleaning previous install directory {INSTALLDIR}")
    try:
        shutil.rmtree(INSTALLDIR)
    except FileNotFoundError:
        pass
    print()

COMMON_OPTS = []

COMMON_OPTS_64 = []
COMMON_OPTS_32 = []

MESA_COMMON_OPTS = []

MESA_COMMON_OPTS += [
    "-Dplatforms=x11,wayland",
    "-Dgallium-extra-hud=true",
    f"-Dvulkan-drivers={args.vulkan_drivers}",
    f"-Dgallium-drivers={args.gallium_drivers}",
    "-Dshader-cache=enabled",
    "-Dvulkan-layers=device-select,overlay,screenshot",  # intel-nullhw
    "-Dopengl=true",
    "-Dgles1=enabled",
    "-Dgles2=enabled",
    "-Degl=enabled",
    "-Dllvm=enabled",
    "-Dlmsensors=enabled",
    "-Dtools=glsl,nir",
    "-Dgallium-va=enabled",
    "-Dglvnd=enabled",
    "-Dgbm=enabled",
    #"-Dglx=gallium-xlib",
    "-Dlibunwind=enabled",  # (also need to disable unwind due to multi-arch issues)
    "-Dvideo-codecs=vc1dec,h264dec,h264enc,h265dec,h265enc,av1dec,av1enc,vp9dec",
    "-Dteflon=true",
    "-Dzstd=enabled",
    # "-Dllvm-orcjit=true",  # for llvmpipe
    # "-Dintel-clc=enabled",
    # "-Dintel-rt=enabled",
    # "-Dvulkan-beta=true",
    # "-Dshared-llvm=disabled",  # Causes linking issues on 32-bit with llvm, because of extra linking to libz3.so, which (because we are using 64-bit llvmconfig), uses 64-bit version and fails to link.
    # "-Damd-use-llvm=false",  # Note, meson.build:1765:4: ERROR: Problem encountered: R600 requires LLVM AMD support.
    "-Dspirv-to-dxil=true",
    "-Dshader-cache-max-size=8G",
    "-Dstatic-libclc=all",
    # "-Dgallium-rusticl=true",  # Enabled seaprately only for 64-bit, and not for 32-bit. Various issues. rustc in debian not multi-arch, needing to use rustup, plus complications in spirv-tools and llvm libraries
    # "-Dsplit-debug=enabled",
]

# TODO(baryluk):

# Interesingly enough, "-Dopencl-spirv=true" compiles even without
# libllvmspirvlib-dev installed.

#"-Dintel-clc=enabled" causes issues:
# src/intel/compiler/meson.build:173:2: ERROR: Tried to mix libraries for machines 0 and 1 in target 'intel_clc' This is not possible in a cross build.

# When doing -Dsplit-debug=enabled we got:
# meson.build:934:3: ERROR: Feature split-debug cannot be enabled: split-debug requires the linker argument -Wl,--gdb-index

# At the moment it is not possible to install valgrind i386 and amd64 at the
# same time in Debian, as it is using monolithic package.
# See https://bugs.debian.org/941160 for details
MESA_COMMON_OPTS_64 = ["-Dvalgrind=enabled"]
MESA_COMMON_OPTS_32 = ["-Dvalgrind=disabled"]

# libdrm also supports valigrind, so also disable it on 32-bit. But support
# of this flag might be removed in the future due to issues:
# https://gitlab.freedesktop.org/mesa/drm/-/issues/63
# Also the value names are different.
LIBDRM_COMMON_OPTS_64 = ["-Dvalgrind=enabled"]
LIBDRM_COMMON_OPTS_32 = ["-Dvalgrind=disabled"]

if args.buildopencl:
    # Also see https://bugs.debian.org/1023780 about multi-arch issues with spirv-tool

    MESA_COMMON_OPTS_64 += ["-Dgallium-rusticl=true"]
    # Building rusticl for i386, requires cross-compiler, but rustc in Debian is
    # not multi-arch. Solution is to uninstall rustc and install rustup, then
    # manually install rustc. But this still causes issues due to spirv-tools
    # and llvm multi-arch problems.
    #
    # For most practical purposes, 64-bit OpenCL should be enough for most
    # people.
    # MESA_COMMON_OPTS_32 += ["-Dgallium-rusticl=true"]

# Common opts for 32-bit and 64-bit, for libdrm and Mesa.
# Ones with _OPT suffix are for optimized build, ones with _DBG suffix are for debug build.

COMMON_OPTS_OPT = ["--buildtype=plain"]
COMMON_OPTS_OPT += ["-Db_ndebug=true"]
# If you really care about library size and maybe improve performance by 0.1%,
# enable stripping. We already are compiling with -g0, so stripping will save
# very little, and make stack traces or use in gdb / valgrind way harder.
# COMMON_OPTS_OPT+=("--strip")
#
# We explicitly pass -mfpmath=sse, otherwise when compiling 32-bit version,
# it will use x87 / non-see for almost everything, which is slower, and
# can't be vectorized, even when using -march=native -msse2, etc.
# With -mfpmath=sse, it will use sse and sse2 almost everywhere, modulo
# few places where the calling conventions (i.e. to glibc) requires passing
# stuff on x87 stack / registers.
COMPILERFLAGS_OPT = "-pipe -march=native -O2 -mfpmath=sse"
if args.heavyopt:
    nproc = capture(["nproc", "--ignore=2"]).strip()
    COMPILERFLAGS_OPT = f"-pipe -march=native -O3 -mfpmath=sse -ftree-vectorize -flto -flto={nproc} -g0 -fno-semantic-interposition"
COMMON_OPTS_OPT += [
    f"-Dc_args={COMPILERFLAGS_OPT}",
    f"-Dcpp_args=-std=c++17 {COMPILERFLAGS_OPT}",
]

# For i387, one can also use -mpc64, to set the 387 in "reduced precision" mode (32 or 64 bit).
# It could be faster than full 80-bit, but that is anecdotal.

COMMON_OPTS_DBG = ["--buildtype=debug"]
COMMON_OPTS_DBG += ["-Db_ndebug=false"]
#COMMON_OPTS_DBG += ["-Db_sanitize=thread"]
COMPILERFLAGS_DBG = "-pipe -march=native -O1 -mfpmath=sse -ggdb -g3 -gz"
# Note: This is working when doing 'meson configure', but I am not 100% sure
# this is correct when passing everything just to initial 'meson'.
# From testing it appears to be working.
COMMON_OPTS_DBG += [
    f"-Dc_args={COMPILERFLAGS_DBG}",
    f"-Dcpp_args=-std=c++17 {COMPILERFLAGS_DBG}",
]

# "-Db_sanitize=thread"


# Build tests.
# MESA_COMMON_OPTS += ["-Dbuild-tests=true"]

# TODO(baryluk): Add option to build with clang, and with thread / address
# sanitizers.

# Even if we do not build 32-bit version, prepare the cross-file anyway.
# This simplifies a bit of scripting.

# Also by BUILDDBG we could theoretically build optimized libdrm, and
# debug mesa, but that is kind of pointless, often you want debug in drm
# too, and it will perform well anyway one way or another.

if not os.path.exists(f"{SOURCEDIR_MESA}/llvm.ini") or not args.incremental:
    with open(f"{SOURCEDIR_MESA}/llvm.ini", "w") as f:
        print(f"""
[binaries]
c = '/usr/bin/x86_64-linux-gnu-gcc-{GCCVERSION}'
cpp = '/usr/bin/x86_64-linux-gnu-g++-{GCCVERSION}'
llvm-config = '/usr/bin/llvm-config-{LLVMVERSION}'
strip = '/usr/bin/x86_64-linux-gnu-strip'
""", file=f)


if not os.path.exists(f"{SOURCEDIR_MESA}/meson-cross-i386.ini") or not args.incremental:
    with open(f"{SOURCEDIR_MESA}/meson-cross-i386.ini", "w") as f:
        print(f"""
[binaries]
c = '/usr/bin/i686-linux-gnu-gcc-{GCCVERSION}'
cpp = '/usr/bin/i686-linux-gnu-g++-{GCCVERSION}'
ar = '/usr/bin/i686-linux-gnu-gcc-ar-{GCCVERSION}'
strip = '/usr/bin/i686-linux-gnu-strip'
pkg-config = '/usr/bin/i686-linux-gnu-pkg-config'
; We are cheating here. We are using 64-bit llvm-config. But we stars align
; it should work (same compiler and linker flags will be used).
llvm-config = '/usr/bin/llvm-config-{LLVMVERSION}'
; llvm-config = '/usr/lib/llvm-{LLVMVERSION}/bin/llvm-config'

rust_ld = '/usr/bin/i686-linux-gnu-gcc-{GCCVERSION}'
rust = ['rustc', '--target', 'i686-unknown-linux-gnu']
; -C linker=gcc -C link-arg=-m32

; set BINDGEN_EXTRA_CLANG_ARGS to either --target=i686-unknown-linux-gnu or -target i686-unknown-linux-gnu

[built-in options]
c_args = ['-m32']
c_link_args = ['-m32']
cpp_args = ['-m32']
cpp_link_args = ['-m32']

[host_machine]
system = 'linux'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
""", file=f)


# opt / dbg, amd64 / i386
def common_build(BUILD_TYPE: str, ARCHITECTURE: str):
    maybeprint()
    if USE_SYSTEM_LIBDRM:
        print(f"Configuring and building {ARCHITECTURE} {BUILD_TYPE} libdrm and Mesa ...")
    else:
        print(f"Configuring and building {ARCHITECTURE} {BUILD_TYPE} Mesa ...")
    maybeprint()

    if BUILD_TYPE == "opt":
        COMMON_OPTS_BUILD_TYPE_SPECIFIC = COMMON_OPTS_OPT
    elif BUILD_TYPE == "dbg":
        COMMON_OPTS_BUILD_TYPE_SPECIFIC = COMMON_OPTS_DBG
    else:
        raise Exception(f"Unknown BUILD_TYPE passed to common_build: {BUILD_TYPE}")


    if ARCHITECTURE == "amd64":
        CC = f"gcc-{GCCVERSION}"
        CXX = f"g++-{GCCVERSION}"
        PKG_CONFIG_ARCH = "x86_64"
        # We use the same cross file for libdrm and mesa. But we keep it in Mesa directory only for convinience.
        CROSS_FILE = f"{SOURCEDIR_MESA}/llvm.ini"
        COMMON_OPTS_ARCH_SPECIFIC = COMMON_OPTS_64
        MESA_COMMON_OPTS_ARCH_SPECIFIC = MESA_COMMON_OPTS_64
        LIBDRM_COMMON_OPTS_ARCH_SPECIFIC = LIBDRM_COMMON_OPTS_64
    elif ARCHITECTURE == "i386":
        CC = f"i686-linux-gnu-gcc-{GCCVERSION}"
        CXX = f"i686-linux-gnu-g++-{GCCVERSION}"
        PKG_CONFIG_ARCH = "i686"
        CROSS_FILE = f"{SOURCEDIR_MESA}/meson-cross-i386.ini"  # ditto.
        COMMON_OPTS_ARCH_SPECIFIC = COMMON_OPTS_32
        MESA_COMMON_OPTS_ARCH_SPECIFIC = MESA_COMMON_OPTS_32
        LIBDRM_COMMON_OPTS_ARCH_SPECIFIC = LIBDRM_COMMON_OPTS_32
    else:
        raise Exception(f"Unknown ARCHITECTURE passed to common_build: {ARCHITECTURE}")

    # So happens that libdrm and mesa both use meson and ninja, and we should be
    # able to use same options and techiniques for both.

    # We just separate the some mesa-specific meson options into MESA_COMMON_OPTS
    # now.

    # We set same --prefix for both libdrm and mesa, that makes it easier later
    # to use pkgconfig, and setup LD_LIBRARY_PATH in general.

    PREFIX = f"{INSTALLDIR}/build-{ARCHITECTURE}-{BUILD_TYPE}/install"
    assert not PREFIX.endswith("/")

    env2 = dict(os.environ)
    env2["CC"] = CC
    env2["CXX"] = CXX
    env2["PKG_CONFIG"] = f"{PKG_CONFIG_ARCH}-linux-gnu-pkg-config"

    if not USE_SYSTEM_LIBDRM:
        maybeprint()
        print(f"libdrm: Configuring and building {ARCHITECTURE} {BUILD_TYPE} build ...")
        maybeprint()

        os.chdir(SOURCEDIR_LIBDRM)

        BUILDDIR_LIBDRM = f"{BUILDDIR}/build-{ARCHITECTURE}-{BUILD_TYPE}/libdrm"

        # At the moment we do not have LIBDRM_COMMON_OPTS (i.e. to select libdrm features or drivers to build).
        # libdrm even with everything enabled build so fast, that there is really no point to exclude things (like vmwgfx API or Nouveau API).

        if not os.path.exists(f"{BUILDDIR_LIBDRM}/build.ninja") or not args.incremental:
            run([*NICE,
                 "meson", "setup", f"{BUILDDIR_LIBDRM}/",
                 f"--prefix={PREFIX}",
                 f"--cross-file={CROSS_FILE}",
                 "-Dtests=false",
                 *COMMON_OPTS,
                 *COMMON_OPTS_ARCH_SPECIFIC,
                 *COMMON_OPTS_BUILD_TYPE_SPECIFIC,
                 *LIBDRM_COMMON_OPTS_ARCH_SPECIFIC], env=env2)

        # run(NICE + ["meson", "configure", f"{BUILDDIR_LIBDRM}/"] + COMMON_OPTS + COMMON_OPTS_ARCH_SPECIFIC + COMMON_OPTS_BUILD_TYPE_SPECIFIC + LIBDRM_COMMON_OPTS_ARCH_SPECIFIC])
        run(NICE + ["ninja", "--quiet", "-C", f"{BUILDDIR_LIBDRM}/"])
        print(f"libdrm: Installing {ARCHITECTURE} {BUILD_TYPE} build ...")
        run(NICE + ["ninja", "--quiet", "-C", f"{BUILDDIR_LIBDRM}/", "install"])

        # Now libdrm is installed, we need to tell PKG_CONFIG to also look for the
        # extra .pc files in the installed directory.

        # Note: This only prepends extra paths. Default paths will still be searched after it.
        # We do not use 'export' and pass it as env variable to meson instead
        # (probably not needed to pass it to ninja).
        PKG_CONFIG_PATH = f"{PREFIX}/lib/pkgconfig"
    else:
        PKG_CONFIG_PATH = None


    maybeprint()
    print(f"mesa: Configuring and building {ARCHITECTURE} {BUILD_TYPE} build ...")
    maybeprint()

    os.chdir(SOURCEDIR_MESA)

    BUILDDIR_MESA = f"{BUILDDIR}/build-{ARCHITECTURE}-{BUILD_TYPE}/mesa"

    # if ARCHITECTURE == "i386":
    #     PKG_CONFIG_PATH = f"/usr/lib/i386-linux-gnu/pkgconfig:{PKG_CONFIG_PATH}" if PKG_CONFIG_PATH else "/usr/lib/i386-linux-gnu/pkgconfig"

    if PKG_CONFIG_PATH is not None:
        env2["PKG_CONFIG_PATH"] = PKG_CONFIG_PATH


    if not os.path.exists(f"{BUILDDIR_MESA}/build.ninja") or not args.incremental:
        run([*NICE,
             "meson", "setup", f"{BUILDDIR_MESA}/",
             f"--prefix={PREFIX}",
             f"--cross-file={CROSS_FILE}",
             *COMMON_OPTS,
             *MESA_COMMON_OPTS,
             *COMMON_OPTS_ARCH_SPECIFIC,
             *COMMON_OPTS_BUILD_TYPE_SPECIFIC,
             *MESA_COMMON_OPTS_ARCH_SPECIFIC], env=env2)

    # run(NICE + ["meson", "configure", f"{BUILDDIR_MESA}/", *COMMON_OPTS, *MESA_COMMON_OPTS, *COMMON_OPTS_ARCH_SPECIFIC, *COMMON_OPTS_BUILD_TYPE_SPECIFIC, *MESA_COMMON_OPTS_ARCH_SPECIFIC])
    run(NICE + ["ninja", "--quiet", "-C", f"{BUILDDIR_MESA}/"])
    print(f"mesa: Installing {ARCHITECTURE} {BUILD_TYPE} build ...")
    run(NICE + ["ninja", "--quiet", "-C", f"{BUILDDIR_MESA}/", "install"])


if args.build64:
    if args.buildopt:
        common_build("opt", "amd64")

    if args.builddebug:
        common_build("dbg", "amd64")

if args.build32:
    # ar is symlink to x86_64-linux-gnu-ar
    # gcc-ar is symlink to gcc-ar-10, and it is symlink to x86_64-linux-gnu-gcc-ar-10
    if args.buildopt:
        common_build("opt", "i386")

    if args.builddebug:
        common_build("dbg", "i386")

maybeprint()
print("Generating source files with environmental variable overrides ...")
maybeprint()


def chmodx(filename):
    os.chmod(filename, mode=0o755)  # -rwxr-xr-x


def generate_wrapper_files(BUILD_TYPE: str) -> None:
    assert BUILD_TYPE in {"opt", "dbg"}

    LD_LIBRARY_PATH = []
    LIBGL_DRIVERS_PATH = []
    VK_LAYER_PATH = []
    VK_ICD_FILENAMES = []
    OCL_ICD_VENDORS = []
    LIBVA_DRIVERS_PATH = []
    PATH_EXTRA = []
    if args.build64:
        LD_LIBRARY_PATH.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/lib")
        LIBGL_DRIVERS_PATH.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/lib/dri")
        VK_LAYER_PATH.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/share/vulkan/explicit_layer.d")
        VK_ICD_FILENAMES.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/share/vulkan/icd.d/radeon_icd.x86_64.json")
        VK_ICD_FILENAMES.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/share/vulkan/icd.d/lvp_icd.x86_64.json")
        OCL_ICD_VENDORS.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/etc/OpenCL/vendors/mesa.icd")
        LIBVA_DRIVERS_PATH.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/lib/dri")
        PATH_EXTRA.append(f"{INSTALLDIR}/build-amd64-{BUILD_TYPE}/install/bin")
    if args.build32:
        LD_LIBRARY_PATH.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/lib")
        LIBGL_DRIVERS_PATH.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/lib/dri")
        VK_LAYER_PATH.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/share/vulkan/explicit_layer.d")
        VK_ICD_FILENAMES.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/share/vulkan/icd.d/radeon_icd.i686.json")
        VK_ICD_FILENAMES.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/share/vulkan/icd.d/lvp_icd.i686.json")
        # OCL_ICD_VENDORS.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/etc/OpenCL/vendors/mesa.icd")
        LIBVA_DRIVERS_PATH.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/lib/dri")
        PATH_EXTRA.append(f"{INSTALLDIR}/build-i386-{BUILD_TYPE}/install/bin")

    with open(f"{HOME}/enable-new-mesa-{BUILD_TYPE}.source", "w") as f:
        print(f"""#!/bin/sh

# Do not execute this file in your shell, instead "source" it using:
#   . ~/enable-new-mesa-{BUILD_TYPE}.source
# or
#   source ~/enable-new-mesa-{BUILD_TYPE}.source
#
# This will have effects only once in the current shell. It will not apply to
# other shells, terminals, users, whole desktop, other running programs, or once
# you close this shell, logout, reboot, etc. It is temporary.
#
# If you want you get remove eventually. It will be regenerated every time you
# run "mesa-build.sh" script to build new Mesa.

echo "Warning: Will remove existing LD_LIBRARY_PATH." >&2
export LD_LIBRARY_PATH="{':'.join(LD_LIBRARY_PATH)}"
export LIBGL_DRIVERS_PATH="{':'.join(LIBGL_DRIVERS_PATH)}"
export VK_LAYER_PATH="{':'.join(VK_LAYER_PATH)}:/usr/share/vulkan/explicit_layer.d"
export VK_ICD_FILENAMES="{':'.join(VK_ICD_FILENAMES)}"
export OCL_ICD_VENDORS="{':'.join(OCL_ICD_VENDORS)}"
export LIBVA_DRIVERS_PATH="{':'.join(LIBVA_DRIVERS_PATH)}"
export PATH="{':'.join(PATH_EXTRA)}:${{PATH}}"

export VK_INSTANCE_LAYERS=VK_LAYER_MESA_overlay
# To enable frametime outputs uncommend next line. It requires modified Mesa.
#export VK_LAYER_MESA_OVERLAY_CONFIG=output_relative_time,fps,frame,frame_timing,gpu_timing,pipeline_graphics,graph_y_zero,output_csv=0,output_per_frame=1,output_flush=0,position=top-right,width=300,output_file=/tmp/mesa_overlay_%T_%p.txt
# This uses some extra modified features, but they will only produce warnings in
# normal Mesa.
# export VK_LAYER_MESA_OVERLAY_CONFIG=output_relative_time,fps,frame,frame_timing,gpu_timing,pipeline_graphics,graph_y_zero,output_csv=0,output_per_frame=1,output_flush=0,position=top-right,width=300
export VK_LAYER_MESA_OVERLAY_CONFIG=fps,frame,frame_timing,gpu_timing,pipeline_graphics,position=top-right,width=300

export GALLIUM_HUD=fps
export DXVK_HUD=full

# If one wishes to use exported dev files, one can use /home/user/mesa/build-i386/install/lib/pkgconfig
# And possible /home/user/mesa/build-i386/install/include , for some state trackers, vulkan_intel.h,
# GL, GLEX, KHR headers.

# Enable NV_mesh_shader
export RADV_PERFTEST=nv_ms
""", end="", file=f)

    with open(f"{HOME}/mesa-{BUILD_TYPE}", "w") as f:
        print(f"""#!/bin/sh

# We keep the existing LD_LIBRARY_PATH and VK_LAYER_PATH, and not erase it unconditionally.
# This is beacuse user might have other libs and layers installed, and want to use them.
# Also, a steam often will provide its own very verbose LD_LIBRARY_PATH to own runtime libraries,
# and they might be required for games to work properly.

export LD_LIBRARY_PATH="{':'.join(LD_LIBRARY_PATH)}:${{LD_LIBRARY_PATH}}"
export LIBGL_DRIVERS_PATH="{':'.join(LIBGL_DRIVERS_PATH)}"
export VK_LAYER_PATH="{':'.join(VK_LAYER_PATH)}:/usr/share/vulkan/explicit_layer.d:${{VK_LAYER_PATH}}"
export VK_ICD_FILENAMES="{':'.join(VK_ICD_FILENAMES)}"
export OCL_ICD_VENDORS="{':'.join(OCL_ICD_VENDORS)}"
export LIBVA_DRIVERS_PATH="{':'.join(LIBVA_DRIVERS_PATH)}"
export PATH="{':'.join(PATH_EXTRA)}:${{PATH}}"

# Enable NV_mesh_shader
export RADV_PERFTEST=nv_ms

# TODO(baryluk): If the path has no "/", maybe use 'env'?

#if which gamemoderun >/dev/null; then
#  exec env gamemoderun "$@"
#else
exec env "$@"
#fi
""", end="", file=f)

    chmodx(f"{HOME}/mesa-{BUILD_TYPE}")

    # A handy wrapper to run with zink.
    with open(f"{HOME}/zink-{BUILD_TYPE}", "w") as f:
        print(f"""#!/bin/sh

exec env MESA_LOADER_DRIVER_OVERRIDE=zink "${{HOME}}/mesa-{BUILD_TYPE}" "$@"
""", end="", file=f)

    chmodx(f"{HOME}/zink-{BUILD_TYPE}")

if args.buildopt:
    generate_wrapper_files("opt")


if args.builddebug:
    generate_wrapper_files("dbg")


with open(f"{HOME}/disable-new-mesa-hud.source", "w") as f:
    print("""#!/bin/sh

unset DXVK_HUD
unset GALLIUM_HUD
unset VK_LAYER_MESA_OVERLAY_CONFIG
unset VK_INSTANCE_LAYERS
""", end="", file=f)


if "DISPLAY" in os.environ:
    maybeprint()
    print("Testing installation ...")
    maybeprint()

    if args.buildopt:
        runner = f"{HOME}/mesa-opt"
    else:
        assert args.buildebug
        runner = f"{HOME}/mesa-dbg"

    test_env = dict(os.environ)

    glxinfo = capture([runner, "glxinfo"], env=test_env)

    if not glxinfo:
        maybeprint()
        print("glxinfo failed! Bad installation of DRI, gallium or other component.", file=sys.stderr)
        maybeprint()
        # See https://gitlab.freedesktop.org/mesa/mesa/-/issues/4236 and https://gcc.gnu.org/bugzilla/show_bug.cgi?id=96817#c17 for details.
        # sys.exit(2)

    print("\n".join(grep(glxinfo, "OpenGL renderer string")))
    if "OpenGL renderer string" not in glxinfo:
        raise Exception("glxinfo failed")

    vulkaninfo = capture([runner, "vulkaninfo"], env=test_env)
    print("\n".join(grep(vulkaninfo, "GPU id")))

    # test_env["RADV_DEBUG"] = "llvm"
    # vulkaninfo_llvm = capture([runner, "vulkaninfo"], env=test_env)
    # print("\n".join(grep(vulkaninfo_llvm, "GPU id")))

    test_env.update({"VK_INSTANCE_LAYERS": "VK_LAYER_MESA_overlay"})
    if not run([runner, "vkcube", "--c", "60"], env=test_env):
        maybeprint()
        print("vkcube failed! Bad installation of vulkan drivers or Mesa overlay layer.", file=sys.stderr)
        maybeprint()
        # sys.exit(2)

    # export VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation
else:
    maybeprint()
    print("Skipping testing because we are running headless (no X server running?)")
    maybeprint()

# Testing SSE, AVX support:

# $ objdump -d "${INSTALLDIR}/install-amd64-opt/install/lib/libvulkan_radeon.so" | grep %ymm | wc -l
# 12225
# $ objdump -d "${INSTALLDIR}/install-amd64-opt/install/lib/libvulkan_radeon.so" | grep %xmm | wc -l
# 41859
# $ objdump -d "${INSTALLDIR}/install-amd64-opt/install/lib/libvulkan_radeon.so" | grep %ymm | grep %xmm | wc -l
# 966
# $ 
# Good.

# $ objdump -d "${INSTALLDIR}/install-i386-opt/install/lib/libvulkan_radeon.so" | grep %xmm | wc -l
# 0
# $ 
# BAD.


#cd $HOME && git clone git://anongit.freedesktop.org/mesa/rbug-gui rbug-gui
#sudo([*APT_INSTALL, "libgtkgl2.0-dev", "libgtkglext1-dev"])

#sudo(["apt-get", "clean"])

print()
print("Build complete and passed basic tests!")
print("Execute one of the following shell commands to enable proper Mesa")
print("library paths and variables in the current shell:")
if args.buildopt:
    maybeprint()
    print(f". \"{HOME}/enable-new-mesa-opt.source\"  # Optimized Mesa build")
if args.builddebug:
    maybeprint()
    print(f". \"{HOME}/enable-new-mesa-dbg.source\"  # Debug Mesa build")
print()

maybeprint()
print("To disable GALLIUM_HUD , DXVK_HUD and MESA_OVERLAY execute (AFTER above):")
print(f". \"{HOME}/disable-new-mesa-hud.source\"")
print()
maybeprint()

print("Alternative run your application with one of these wrapper scripts:")
maybeprint()
if args.buildopt:
    print(f"{HOME}/mesa-opt")
    print(f"{HOME}/zink-opt")
    maybeprint()
if args.builddebug:
    print(f"{HOME}/mesa-dbg")
    print(f"{HOME}/zink-dbg")
    maybeprint()

maybeprint()
print("All generated scripts use absolute paths, so you can move / relocate them")
print("as you wish (i.e. into your PATH, like ~/bin, or ~/.local/bin). Or safely remove.")
maybeprint()

maybeprint()
maybeprint("Bye!")
