project('mirrorbrain', 'c',
    version: '2.20.0',
    license: 'GPL-2.0',
    meson_version: '>= 0.54.0',
)

apxs = find_program(['apxs2', 'apxs'], required: true)
apache_libexecdir = run_command(apxs, '-q', 'LIBEXECDIR').stdout().strip()
apache_includedir = run_command(apxs, '-q', 'INCLUDEDIR').stdout().strip()

apr = dependency('apr-1', required: true)

subdir('mod_mirrorbrain')
subdir('mod_autoindex_mb')
subdir('mb')
subdir('tools')