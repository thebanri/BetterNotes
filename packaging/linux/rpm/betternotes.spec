# Built by packaging/linux/rpm/build-rpm.sh, which passes the version from
# Cargo.toml as pkg_version and a tarball of the source tree as Source0.
%global debug_package %{nil}
# The Qt glue is C++ that cxx-qt builds into static archives for a Rust link;
# keep it as ordinary object code.
%global _lto_cflags %{nil}

Name:           betternotes
Version:        %{pkg_version}
Release:        1%{?dist}
Summary:        Sticky notes for the Linux desktop
License:        MIT
URL:            https://github.com/thebanri/BetterNotes
Source0:        betternotes-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtbase-private-devel
BuildRequires:  layer-shell-qt-devel
BuildRequires:  wayland-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  sqlite-devel
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

# Loaded at run time, so the automatic library dependencies miss them.
Requires:       qt6-qtdeclarative
Requires:       qt6-qtwayland
Requires:       hicolor-icon-theme

%description
BetterNotes keeps notes as independent sticky windows on the desktop, with
rich text, links, tags, full-text search, reminders, and a library window for
finding and organising them. Notes are stored locally in SQLite.

%prep
%autosetup -n BetterNotes-%{version}

%build
export QMAKE=%{_qt6_qmake}
cargo build --release --locked -p betternotes

%install
packaging/linux/stage.sh %{buildroot} target/release/betternotes

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/org.betternotes.BetterNotes.desktop
appstream-util validate-relax --nonet %{buildroot}%{_metainfodir}/org.betternotes.BetterNotes.metainfo.xml
export QMAKE=%{_qt6_qmake}
cargo test --release --locked

%files
%license LICENSE
%{_bindir}/betternotes
%{_datadir}/applications/org.betternotes.BetterNotes.desktop
%{_metainfodir}/org.betternotes.BetterNotes.metainfo.xml
%{_datadir}/icons/hicolor/scalable/apps/org.betternotes.BetterNotes.svg
%{_datadir}/icons/hicolor/*/apps/org.betternotes.BetterNotes.png
