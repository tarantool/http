Name: tarantool-http
Version: 1.1.1
Release: 1%{?dist}
Epoch: 1
Summary: HTTP server for Tarantool
Group: Applications/Databases
License: BSD
URL: https://github.com/tarantool/http
Source0: https://github.com/tarantool/%{name}/archive/%{version}/%{name}-%{version}.tar.gz
BuildRequires: cmake >= 2.8
BuildRequires: gcc >= 4.5
BuildRequires: tarantool-devel >= 1.7.5.0
BuildRequires: /usr/bin/prove
Requires: tarantool >= 1.7.5.0

%description
This package provides a HTTP server for Tarantool.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo
%if 0%{?fedora} >= 33 || 0%{?rhel} >= 8
  %cmake_build
%else
  %make_build
%endif

%install
%if 0%{?fedora} >= 33 || 0%{?rhel} >= 8
  %cmake_install
%else
  %make_install
%endif

%files
%{_libdir}/tarantool/*/
%{_datarootdir}/tarantool/*/
%doc README.md
%{!?_licensedir:%global license %doc}
%license LICENSE AUTHORS

%changelog
* Thu Feb 18 2016 Roman Tsisyk <roman@tarantool.org> 1.0.0-1
- Initial version of the RPM spec
