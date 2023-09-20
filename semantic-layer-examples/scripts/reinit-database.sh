#!/bin/sh


eng=$1
db=$2
pro=$3

if [ "$2" == "" ]; then
    echo "Missing command line parameter. Use it from the root of the repository:\n\n\t bin/init_database.sh  engine_name  database_name  [profile_name]\n"
    exit 1
fi

if [ "$3" == "" ]; then
    pro="default"
fi

# recreate the database
if [[ `rai list-databases --profile $pro | grep -o $db` ]]; then
    rai delete-database $db --profile $pro
fi
rai create-database $db --profile $pro

echo "Loading base data..."
for rel in rel/update/*; do
    # echo "running read-write query '$rel' against database '$db'"
    rai --profile $pro --engine $eng exec $db --file $rel
done
echo "Base data loaded."

echo "Loading models..."
find rel/model -type f | while read -r file; do

    path="${file%/*}"  # Extract the last segment of the path
    filename="${file##*/}"     # Extract the filename
    last_segment="${path//rel\//}"
    model="$last_segment/$filename"

    rai --profile $pro --engine $eng load-model $db $file --model $model
    echo "installing '$file' into database '$db'"
done
echo "Models loaded."

