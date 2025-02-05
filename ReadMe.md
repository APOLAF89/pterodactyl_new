# ![](https://cdn.discordapp.com/attachments/833023359817220169/1018069492770820146/Pterodactyl.png)Pterodactyl

![](https://cdn.discordapp.com/attachments/833023359817220169/1018084512112066651/Bash-.png) Install script:
```sh
bash <(curl -s https://raw.githubusercontent.com/APOLAF89/pterodactyl_new/main/pterodactyl.sh)
```

Options:
```js
[0] Exit

[1] Install panel

[2] Install wings

[3] Install panel & wings

[4] Update panel

[5] Uninstall panel & wings

[6] Install theme

[7] Install phpMyAdmin

[8] Uninstall phpMyAdmin
```


Create SSL certificates with Certbot
```yml
apt update && apt install -y certbot python3-certbot-nginx

certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d domain.com
```
