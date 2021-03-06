#!/bin/bash

# poner en crontab, a conveniencia
# * * * * * /bin/bash -l -c /home/user/check_gmail.sh
# depende de yad, sox, python-keyring, firefox... 
# necesita info de dbus si se ejecuta desde fuera de X (como en crontab)

accounts=("ruben@elpulgardelpanda.com")

file_name="check_gmail.sh"
notify_flag="$HOME/.check_gmail_notified.flag"
directory=$(cd `dirname $0` && pwd)
log="$directory/check_gmail.log"
source $HOME/.Xdbus # dbus info

function check_account() {
  gmail_login="$1"
  gmail_password=$(python -c "import keyring;print keyring.get_password('""$file_name""', '""$gmail_login""')")
  if [ "None" = "$gmail_password" ]; then
    gmail_password=$(zenity --password --title="$gmail_login")
    python -c "import keyring;print keyring.set_password('""$file_name""', '""$gmail_login""', '""$gmail_password""')" > /dev/null
  fi
  gmail_xml=$(wget -q -O - https://mail.google.com/a/gmail.com/feed/atom --http-user=${gmail_login} --http-password=${gmail_password} --no-check-certificate)
  count=$(echo $gmail_xml | sed 's/^.*<fullcount>\([0-9]*\)<\/fullcount>.*$/\1/')

  if [ $count -gt 0 ]; then
    echo "[$(date)] $count emails in $gmail_login !" >> $log
    #extract entries one by one
    msg=""
    sep="\n"
    rest="$gmail_xml"
    for (( i=0 ; i < $count ; i++ )); do
      entry_xml=$(echo $rest | sed 's/\(.*\)\(<entry>.*<\/entry>\)\(.*\)/\2/')
      rest=$(echo $rest | sed 's/\(.*\)\(<entry>.*<\/entry>\)\(.*\)/\1/')
      title=$(echo $entry_xml | sed 's/.*<title>\(.*\)<\/title>.*/\1/')
      summary=$(echo $entry_xml | sed 's/.*<summary>\(.*\)<\/summary>.*/\1/')
      author=$(echo $entry_xml | sed 's/.*<author>.*<email>\(.*\)<\/email>.*<\/author>.*/\1/')
      name=$(echo $entry_xml | sed 's/.*<author>.*<name>\(.*\)<\/name>.*<\/author>.*/\1/')
      mail_url_params=$(echo $entry_xml | sed 's/.*<link \(.*\) \/>.*/\1/' | sed 's/.*href=".*?\(.*\)" .*/\1/' | sed 's/\&amp;/\&/g')
      msg="$msg($name):$title$sep"
    done
    msg=$(echo $msg | sed 's/"//g')
    notify-send "$gmail_login ($count)" "\n$msg" -i emblem-ohno &>> $log
    play -q /usr/share/sounds/freedesktop/stereo/dialog-warning.oga reverse repeat repeat repeat vol 5 &>> $log
    if [ ! -f $notify_flag ]; then
      touch $notify_flag

      # add handler for tray icon left click
      function on_click() {
        url="http://mail.google.com?$1"
        firefox --new-tab $url
      }
      export -f on_click

      cmd="bash -c \"on_click '$mail_url_params'\""
      yad --notification --image=emblem-ohno  --text="$gmail_login ($count)" --command="$cmd" # block until notification is cleaned
      rm $notify_flag
    fi
  fi
}

for account in "${accounts[@]}"
do
  echo -n '.' >> $log
  check_account $account &>> $log
  sleep 10 # yes, sleep between accounts, let notify do its job
done
