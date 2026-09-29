<div align="center">
  <h1>🏗️ Архитектура и Workflow проекта</h1>
  <p><b>luci-app-telemt v3.x.x - апплет для управления сервисом MTProxy telemt на OpenWRT роутерах</b> 
    <p><i>Как веб-интерфейс, инит-система и бинарник соображают на троих</i></p>
</div>

<hr>

<h2>📂 1. Структура папок и файлов</h2>
<p>Репозиторий зеркалирует корневую файловую систему OpenWrt. При установке пакет раскидывает файлы ровно по этой схеме:</p>

<pre style="background-color: rgba(27,31,35,0.05); padding: 16px; border-radius: 6px; font-family: monospace; line-height: 1.4;">
📦 luci-app-telemt
 ┣ 📂 root/
 ┃ ┣ 📂 etc/
 ┃ ┃ ┣ 📂 config/
 ┃ ┃ ┃ ┗ 📜 <b>telemt</b>                 <span style="color: #6a737d;">// Дефолтный конфиг UCI (Священный Грааль настроек)</span>
 ┃ ┃ ┗ 📂 uci-defaults/
 ┃ ┃   ┗ 📜 <b>luci-telemt</b>            <span style="color: #6a737d;">// Post-install хук (регистрирует меню в LuCI)</span>
 ┃ ┗ 📂 usr/
 ┃   ┣ 📂 bin/
 ┃   ┃ ┗ ⚙️ <b>telemt</b>                 <span style="color: #d73a49;">// [Внешняя зависимость] Сам Rust-бинарник, ставится отдельно</span>
 ┃   ┣ 📂 lib/lua/luci/model/cbi/
 ┃   ┃ ┗ 📜 <b>telemt.lua</b>             <span style="color: #6a737d;">// 🧠 Мозги: Контроллер веб-интерфейса и повелитель AJAX</span>
 ┃   ┗ 📂 share/telemt-luci/
 ┃     ┗ 📜 <b>init_script</b>            <span style="color: #6a737d;">// ⚙️ Пламенный мотор: Procd init.d скрипт и кодогенератор TOML</span>
 ┣ 📜 Makefile                     <span style="color: #6a737d;">// Рецепт сборки .ipk для суровых парней с OpenWrt SDK</span>
 ┣ 📜 owfeed.yml                    <span style="color: #6a737d;">// owfeed package definition (IPK for 24.10, APKv3 for 25.12) — see RELEASING.md</span>
 ┗ 📜 tools/stage.sh                 <span style="color: #6a737d;">// stages root/ + scripts/ into dist/ for owfeed</span>
</pre>

<hr>

<h2>📦 2. Жизненный цикл пакета (Install / Update / Remove)</h2>
<p>Как система управляет пакетом и почему ваши данные никогда не превращаются в тыкву при обновлениях:</p>

<details open>
  <summary><b><span style="font-size: 1.1em;">📥 Установка (Install)</span></b></summary>
  <div style="padding-left: 20px; margin-top: 5px; margin-bottom: 10px;">
    ОС распаковывает файлы в корень. Затем молча запускается <code>/etc/uci-defaults/luci-telemt</code>. Этот скрипт регистрирует вкладку в LuCI, вычищает кэши веб-сервера (чтобы раздел появился без ребута) и совершает суицид (удаляет сам себя, как и положено <code>uci-defaults</code> скриптам в OpenWrt). Файл <code>init_script</code> линкуется в <code>/etc/init.d/telemt</code>.
  </div>
</details>

<details open>
  <summary><b><span style="font-size: 1.1em;">🔄 Обновление (Upgrade) и бессмертие настроек</span></b></summary>
  <div style="padding-left: 20px; margin-top: 5px; margin-bottom: 10px;">
    Почему при установке новой версии <code>.ipk</code> ваши юзеры и секреты не затираются дефолтным файлом из пакета? Потому что <code>/etc/config/telemt</code> помечен в манифесте сборки как <b>conffile</b>. Пакетный менеджер <code>opkg</code> видит это и <i>никогда</i> не перезаписывает измененный пользователем конфиг. Новый дефолтный конфиг из пакета тихо падает рядом с расширением <code>.opkg-new</code>, оставляя вашу базу целой и невредимой.
  </div>
</details>

<details open>
  <summary><b><span style="font-size: 1.1em;">🗑️ Удаление (Remove / Purge)</span></b></summary>
  <div style="padding-left: 20px; margin-top: 5px; margin-bottom: 10px;">
    При запуске <code>opkg remove</code> срабатывает <b>prerm</b> (pre-remove) скрипт. Он штатно гасит демона (<code>/etc/init.d/telemt stop</code>), чтобы прокси не остался висеть зомби-процессом в памяти. Затем удаляются скрипты из <code>/usr/lib/</code>. <b>Внимание:</b> сам конфиг <code>/etc/config/telemt</code> остается в системе! Если вы хотите снести пакет с корнями, нужно делать <code>opkg remove --autoremove luci-app-telemt</code> или удалять файл настроек руками.
  </div>
</details>

<hr>

<h2>🧩 3. Зоны ответственности (Кто за что страдает)</h2>

<details open>
  <summary><b><span style="font-size: 1.2em;">🖥️ Контроллер веб-интерфейса (<code>telemt.lua</code>)</span></b></summary>
  <div style="padding-left: 20px; margin-top: 10px;">
    <ul>
      <li><b>Биндинг:</b> Намертво привязывает HTML-формы к файлу <code>/etc/config/telemt</code> (UCI). Что написал в браузере, то и упало в конфиг.</li>
      <li><b>Санитария и защита от инъекций:</b> Весь инпут от пользователя (имена, порты, IP) жестко фильтруется регулярными выражениями на бэкенде. Спецсимволы экранируются, чтобы никто не прокинул произвольный шелл-код через <code>sys.call()</code> или не развалил структуру UCI-конфига.</li>
      <li><b>📦 БД и CSV-магия (Import/Export):</b> Скрипт умеет выплевывать базу юзеров и живую статистику трафика в CSV (удобно для биллинга). При импорте работает жесткий фейс-контроль: Lua-бэкенд проверяет CSV на кривую кодировку, отрезает BOM-маркеры, валидирует 32-символьные hex-секреты (умно удаляя случайные префиксы <code>ee</code>/<code>dd</code>, если админ криво скопипастил) и фильтрует мусор. Загружать пользователей можно в двух режимах: <b>Replace</b> (сжечь старую базу дотла и залить новую) и <b>Merge</b> (аккуратное слияние, где обновляются только совпавшие юзеры).</li>
      <li><b>AJAX Эндпоинты:</b> Перехватывает <code>GET/POST</code> запросы, чтобы тащить живые метрики Prometheus, парсить логи демона и чекать статус портов в файерволе без перезагрузки страницы.</li>
      <li><b>Мутация DOM & Graceful Degradation:</b> JS-пейлоад детектит версию OpenWrt. Если видит поехавший LuCI2 VDOM (OpenWrt 25.x), скрипт динамически инжектит <code>[ user: name ]</code> прямо в ячейку с Secret. VDOM обманут, таблица не разваливается, админ спокоен.</li>
    </ul>
  </div>
</details>

<details open>
  <summary><b><span style="font-size: 1.2em;">⚙️ Init-скрипт и TOML-генератор (<code>init_script</code>)</span></b></summary>
  <div style="padding-left: 20px; margin-top: 10px;">
    <ul>
      <li><b>Дрессировка Procd:</b> Рулит демоном (start/stop/reload), настраивает лимиты респавна и раздвигает лимиты файловых дескрипторов (<code>nofile=65536</code>).</li>
      <li><b>Умная генерация конфига:</b> Читает UCI и собирает минималистичный <code>/var/etc/telemt.toml</code>. Если какая-либа опция выключена в Luci — в конфиге TOML её не будет.</li>
      <li><b>Защита от дурака (Foolproof):</b> Встроенные функции <code>is_cidr</code> и <code>is_uint</code> не дадут подсунуть текст вместо чисел. Если админ решит вписать домен в поле, где бинарник ждет строгий IPv4, скрипт проигнорирует этот мусор, спасая Rust-парсер от панической атаки (Panic).</li>
      <li><b>Суровый парсинг версии:</b> Скрипт достает версию бинарника для отображения в UI, используя команду <code>grep -a -m1 -i 'MTProxy v' /usr/bin/telemt</code>. <b>Почему мы не делаем красиво через <code>telemt --version</code>?</b> Потому что запуск бинарника только ради вывода версии может привести к зомби, выдать ошибку конфига или просто сожрать процессорное время. Выдирание строки прямо из конца специально скомпилированного файла через <code>grep</code> работает безотказно и моментально.</li>
      <li><b>Обход глухого NAT (STUN Fallback):</b> Если провайдер режет UDP/STUN, скрипт замечает выключенный человеком STUN в настройках и жестко скармливает Announce IP в листенеры. В итоге Middle-End Proxy поднимается даже за CGNAT. Но радости от этого обычно нет.</li>
      <li><b>RAM Metrics Dump (Спасение квот):</b> При получении сигнала на остановку, скрипт дергает метрики через <code>uclient-fetch</code> и сбрасывает аккумулированный трафик в <code>/tmp/telemt_stats.txt</code>. Ребут демона больше не обнуляет квоты!</li>
      <li><b>Динамический Firewall:</b> Общается с Procd JSON API, чтобы молча открыть порт в RAM. Остановили сервис — порт исчез. Никаких грязных следов в постоянных правилах.</li>
    </ul>
  </div>
</details>

<hr>

<h2>🔄 4. Операционный Workflow (Как всё крутится)</h2>
<p>Как данные гуляют от браузера админа до сурового Rust-бинарника и обратно:</p>

<table style="width:100%; text-align:left; border-collapse: collapse;">
  <tr style="background-color: rgba(0, 160, 0, 0.1);">
    <th style="padding: 10px; border: 1px solid #ddd;">Этап</th>
    <th style="padding: 10px; border: 1px solid #ddd;">Компонент</th>
    <th style="padding: 10px; border: 1px solid #ddd;">Что происходит</th>
  </tr>
  <tr>
    <td style="padding: 10px; border: 1px solid #ddd;"><b>1. Save</b></td>
    <td style="padding: 10px; border: 1px solid #ddd;">🌐 Web UI (LuCI)</td>
    <td style="padding: 10px; border: 1px solid #ddd;">Юзер жмет "Save & Apply". LuCI бережно записывает настройки в <code>/etc/config/telemt</code>.</td>
  </tr>
  <tr>
    <td style="padding: 10px; border: 1px solid #ddd;"><b>2. Trigger</b></td>
    <td style="padding: 10px; border: 1px solid #ddd;">🛠️ System (Ubus)</td>
    <td style="padding: 10px; border: 1px solid #ddd;">OpenWrt (через подсистему ubus) замечает, что конфиг изменился, и дает пинка скрипту: <code>/etc/init.d/telemt reload</code>.</td>
  </tr>
  <tr>
    <td style="padding: 10px; border: 1px solid #ddd;"><b>3. Generate</b></td>
    <td style="padding: 10px; border: 1px solid #ddd;">⚙️ Init Script</td>
    <td style="padding: 10px; border: 1px solid #ddd;">Скрипт просыпается, применяет логику STUN, фильтрует инпут и выгружает свежий <code>/var/etc/telemt.toml</code> в tmpfs (RAM).</td>
  </tr>
  <tr>
    <td style="padding: 10px; border: 1px solid #ddd;"><b>4. Execution</b></td>
    <td style="padding: 10px; border: 1px solid #ddd;">🚀 Procd</td>
    <td style="padding: 10px; border: 1px solid #ddd;">Запускает бинарник <code>telemt</code>, скармливает ему свежий TOML и молча прокидывает правило в файерволе.</td>
  </tr>
  <tr>
    <td style="padding: 10px; border: 1px solid #ddd;"><b>5. Telemetry</b></td>
    <td style="padding: 10px; border: 1px solid #ddd;">📡 Telemt Binary</td>
    <td style="padding: 10px; border: 1px solid #ddd;">Rust-сервер начинает пускать клиентов, кэширует профили эмуляции TLS в <code>/var/etc/telemt_tlsfront/</code> и вывешивает метрики на <code>127.0.0.1:9091</code>.</td>
  </tr>
  <tr>
    <td style="padding: 10px; border: 1px solid #ddd;"><b>6. Feedback</b></td>
    <td style="padding: 10px; border: 1px solid #ddd;">🌐 Web UI (JS)</td>
    <td style="padding: 10px; border: 1px solid #ddd;">Раз в 2.5 секунды JS в браузере дергает AJAX, парсит сырой текст Prometheus, считает дельту и рисует красивые скорости и зеленые индикаторы онлайна.</td>
  </tr>
</table>

<hr>

<h2>🚦 5. Жизненный цикл сервиса под капотом</h2>
<ul>
  <li>🟢 <b>START:</b> Обычная рутина. Читаем UCI -> Генерим TOML -> <code>procd_open_instance</code> -> Запуск бинарника -> Открытие порта.</li>
  <li>🔴 <b>STOP:</b> Сначала срабатывает функция-перехватчик <code>run_save_stats</code>. Она стучится к локальному Prometheus, забирает последние байты, плюсует их к старым записям и пишет в <code>/tmp/</code>. Только после этого посылается <code>SIGKILL</code> процессу. Файервол закрывается сам силами Procd.</li>
  <li>🔄 <b>RESTART:</b> Выполняет мягкий STOP со сбросом метрик, а затем чистый START. Статистика юзеров бесшовно склеивается.</li>
</ul>

<hr>

<h2>🐛 6. Оставшиеся баги (Они же — известные особенности)</h2>
<ul>
  <li><b>Экстремальный ресайз в 25.x:</b> LuCI2 VDOM всё еще может немного "поплыть", если агрессивно дергать ширину окна браузера туда-сюда на странице с пользователями. Смиритесь, это особенность поведения виртуального DOM.</li>
  <li><b>IPv6 + Middle Proxy:</b> Экспериментальная рулетка. Зависит от того, как маршрутизация сойдется у провайдера. STUN по IPv6 пробивается далеко не везде.</li>
  <li><b>Амнезия при хард-резете:</b> Если выдернуть роутер из розетки (или вручную удалить <code>/tmp/telemt_stats.txt</code>), не дождавшись штатного завершения службы, вся статистика трафика за текущую сессию испарится навсегда.</li>
</ul>

<hr>

<h2>🚀 7. Roadmap (Перспективы развития)</h2>
<ul>
  <li>[ ] Интеграция клиентского рендеринга графиков (Chart.js), чтобы рисовать красивые дашборды трафика (если уложимся в размер пакета для ПЗУ роутеров).</li>
  <li>[ ] Интеграция Telegram-уведомлений через бота <i>(«Шеф, юзер Вася сожрал свою квоту!»)</i>.</li>
  <li>[ ] Поддержка фичи условного прослушивания (Conditional listening) из будущей ветки Telemt 3.2.x.</li>
</ul>

<br>
<p align="center">
  <i>Сделано роботами, и немножко потом и кровью медведя для OpenWrt 21.02 — 25.x 🚀</i>
</p>
