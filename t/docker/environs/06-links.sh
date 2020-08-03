#!../lib/test-in-container-environs.sh
set -ex

[ -d mirrorbrain ]

./environ.sh pg9-system2
./environ.sh ap9-system2
./environ.sh ap8-system2
./environ.sh ap7-system2
./environ.sh mb9 $(pwd)/mirrorbrain

pg9*/start.sh

ap9=$(ls -d ap9*)

mb9*/configure_db.sh pg9
mb9*/configure_apache.sh ap9

# populate test data
for x in ap7 ap8 ap9; do
    xx=$(ls -d $x*/)
    mkdir -p $xx/dt/downloads/folder1
    touch $xx/dt/downloads/folder1/file1.dat
done

mb9*/mb.sh makehashes $PWD/ap9-system2/dt/

ap9*/start.sh
ap9*/status.sh
# ap9*/curl.sh downloads/folder1/ | grep file1.dat
ap9*/curl.sh downloads/ | grep folder1

for x in ap7 ap8; do
    $x*/start.sh
    $x*/status.sh
    mb9*/mb.sh new $x --http http://"$($x-system2/print_address.sh)" --region NA --country us
    mb9*/mb.sh scan --enable $x
    $x-system2/curl.sh | grep downloads
done

# first linked folder with name with the same lenght as target
ap9*/curl.sh /downloads/folder1/file1.dat

# create a file inside DocumentDir and create a link to it:
echo testInside > ap9-system2/dt/downloads/fileInside.dat
ln -s $(pwd)/ap9*/dt/downloads/fileInside.dat $(pwd)/ap9*/dt/downloads/folder1/

# create files outside of DocumentDir and create a link to each:
mkdir -p ap9-system2/x
echo testShortOutside > ap9-system2/x/fileShortOutside.dat
ln -s $(pwd)/ap9*/x/fileShortOutside.dat $(pwd)/ap9*/dt/downloads/folder1/
mkdir -p ap9-system2/folder2verylonglongname
echo testLongOutside > ap9-system2/folder2verylonglongname/fileLongOutside.dat
ln -s $(pwd)/ap9*/folder2verylonglongname/fileLongOutside.dat $(pwd)/ap9*/dt/downloads/folder1/

res1=$(ap9*/curl.sh /downloads/folder1/fileInside.dat)
grep 'File is on mirror base -> using real name' ap9*/dt/error_log
res2=$(ap9*/curl.sh /downloads/folder1/fileShortOutside.dat)
grep 'File is not on mirror base -> using original name' ap9*/dt/error_log
res3=$(ap9*/curl.sh /downloads/folder1/fileLongOutside.dat)
test 2 == $(grep 'File is not on mirror base -> using original name' ap9*/dt/error_log | wc -l)

[ "${res1}" == testInside ]
[ "${res2}" == testShortOutside ]
[ "${res3}" == testLongOutside ]
