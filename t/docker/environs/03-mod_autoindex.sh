#!../lib/test-in-container-environs.sh
set -ex

[ -d mirrorbrain ]

./environ.sh pg9-system2
./environ.sh ap9-system2
./environ.sh mb9 $(pwd)/mirrorbrain

pg9*/start.sh

mb9*/configure_db.sh pg9
mb9*/configure_apache.sh ap9

ap9=$(ls -d ap9*)

# delete mod_autoindex
sed -i '/autoindex_module/d' ap9*/httpd.conf
# configure mod_autoindex_mb
echo "LoadModule autoindex_mb_module  $PWD/mb9/src/build/mod_autoindex_mb/mod_autoindex_mb.so" >> ap9*/extra-mirrorbrain.conf 


# populate test data
for x in ap9; do
    xx=$(ls -d $x*/)
    mkdir -p $xx/dt/downloads/{folder1,folder2,folder3}
    echo $xx/dt/downloads/{folder1,folder2,folder3}/{file1,file2}.dat | xargs -n 1 touch
done

ap9*/start.sh

ap9*/curl.sh downloads/ | grep folder1
ap9*/curl.sh downloads/folder1/?F=J | grep '"file1.dat",' | grep '"file2.dat",'
ap9*/curl.sh downloads/folder1/?F=J
ap9*/curl.sh downloads/folder1/?F=J | jsonlint


