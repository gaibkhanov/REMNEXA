#requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Name,

    [switch]$DryRun,
    [switch]$IncludeUserFiles,
    [switch]$ResidualOnly,
    [switch]$NoRestorePoint,
    [switch]$NoElevation,
    [switch]$OverrideProtectedComponent,
    [switch]$RemoveProvisionedAppx,
    [switch]$TestIntegrity,
    [switch]$SelfTest,
    [switch]$ResumeRemoval,
    [switch]$ContinueInteractive,
    [ValidateSet('', 'Registry', 'Features', 'Privacy', 'Antivirus', 'Startup')]
    [string]$ToolMode = '',
    [ValidateSet('', 'Home', 'Uninstall', 'Antivirus', 'Startup', 'Services')]
    [string]$WorkspaceMode = '',
    [string]$SelectedRegistryPath,
    [string]$SelectedPackageFullName,
    [string]$SelectedStartupId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:BrandName = 'REMNEXA'
$script:CleanerVersion = '2.1.3'
$script:RestartRequired = $false
$script:ExitRequested = $false
$script:LastRunLogPath = ''
$script:LastRunSummary = $null
$script:ReturnToProgramList = $false
$script:LogLines = New-Object System.Collections.Generic.List[string]
$global:ProgramCleanerLogLines = $script:LogLines
$global:RemnexaLogLines = $script:LogLines
$script:TraceIndex = @{}
$script:InteractiveSession = $false
$script:ProvisionedRemovedCount = 0
$script:ProtectedOverrideCategory = ''
$script:LanguageCodes = @('de', 'en', 'es', 'fr', 'ru', 'tr')
$script:Language = 'de'
$script:LegacyDataRoot = Join-Path $env:LOCALAPPDATA 'ProgramCleaner'
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'REMNEXA'
$script:SettingsPath = Join-Path $script:DataRoot 'Settings.json'
$script:HistoryPath = Join-Path $script:DataRoot 'History.jsonl'
$script:LogRoot = Join-Path $script:DataRoot 'Logs'
$script:PrivacyBackupPath = Join-Path $script:DataRoot 'PrivacyBackup.json'
$script:StartupHistoryPath = Join-Path $script:DataRoot 'StartupHistory.jsonl'
$script:StartupBackupRoot = Join-Path $script:DataRoot 'StartupBackups'
$script:AntivirusModulePath = Join-Path $PSScriptRoot 'Antivirus\Antivirus.psd1'
$script:AntivirusAvailable = $false
$script:ProtectedServices = @(
    'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wscsvc',
    'wuauserv', 'WaaSMedicSvc', 'UsoSvc', 'BITS', 'DoSvc',
    'InstallService', 'AppXSvc', 'ClipSVC'
)
$script:ProtectedComponents = @(
    [PSCustomObject]@{ Category = 'Windows Defender / Security Center'; Pattern = '(?i)(Windows|Microsoft)\s*(Defender|Security)|Security\s*Center|SecHealth|SecurityHealth|Microsoft\.SecHealthUI' },
    [PSCustomObject]@{ Category = 'Windows Update'; Pattern = '(?i)^Windows\s*Update($|\s)|Update\s*Health\s*Tools|WaaSMedic|UsoSvc|\bwuauserv\b' },
    [PSCustomObject]@{ Category = 'Microsoft Store infrastructure'; Pattern = '(?i)^Microsoft\s*Store$|Windows\s*Store|Microsoft\.WindowsStore|StorePurchaseApp|DesktopAppInstaller|App\s*Installer|\bAppXSvc\b|\bClipSVC\b' },
    [PSCustomObject]@{ Category = '.NET Framework / Runtime'; Pattern = '(?i)Microsoft\s*\.NET|\.NET\s*(Framework|Runtime|Desktop Runtime|Host)|ASP\.NET\s*Core|\bNetFx\d' },
    [PSCustomObject]@{ Category = 'Microsoft Visual C++ Redistributable'; Pattern = '(?i)Microsoft\s*Visual\s*C\+\+.*(Redistributable|Runtime)|VC\+\+.*Runtime' }
)

# Reihenfolge aller Übersetzungen: Deutsch, Englisch, Spanisch, Französisch, Russisch, Türkisch.
$script:Texts = @{
    AppDescription       = @('Deinstalliert ein ausgewähltes Windows-Programm und sucht danach nach Resten.', 'Uninstalls a selected Windows program and then searches for leftovers.', 'Desinstala un programa de Windows y después busca restos.', 'Désinstalle un programme Windows puis recherche les résidus.', 'Удаляет выбранную программу Windows, а затем ищет её остатки.', 'Seçilen Windows programını kaldırır ve ardından kalıntıları arar.')
    AdminDeferred        = @('Administratorrechte werden erst nach Auswahl [1] angefordert.', 'Administrator rights are requested only after selecting [1].', 'Los derechos de administrador se solicitan solo después de elegir [1].', 'Les droits administrateur ne sont demandés quʼaprès le choix [1].', 'Права администратора запрашиваются только после выбора [1].', 'Yönetici hakları yalnızca [1] seçildikten sonra istenir.')
    SelectPrompt         = @('Auswahl', 'Selection', 'Selección', 'Sélection', 'Выбор', 'Seçim')
    SearchPrompt         = @('Suchtext', 'Search text', 'Texto de búsqueda', 'Texte recherché', 'Текст поиска', 'Arama metni')
    MainQuestion         = @('Was möchtest du tun?', 'What would you like to do?', '¿Qué deseas hacer?', 'Que souhaitez-vous faire ?', 'Что вы хотите сделать?', 'Ne yapmak istiyorsunuz?')
    Main1                = @('Programm über den Namen suchen', 'Search for a program by name', 'Buscar un programa por nombre', 'Rechercher un programme par nom', 'Найти программу по имени', 'Programı adına göre ara')
    Main2                = @('Installierte Anwendungen auflisten (empfohlen)', 'List installed applications (recommended)', 'Listar aplicaciones instaladas (recomendado)', 'Lister les applications installées (recommandé)', 'Показать установленные приложения (рекомендуется)', 'Yüklü uygulamaları listele (önerilen)')
    Main3                = @('Alle Einträge einschließlich Systemkomponenten anzeigen', 'Show all entries including system components', 'Mostrar todas las entradas, incluidos los componentes del sistema', 'Afficher toutes les entrées, y compris les composants système', 'Показать все записи, включая системные компоненты', 'Sistem bileşenleri dahil tüm kayıtları göster')
    Main4                = @('Nur Reste eines bereits entfernten Programms suchen', 'Search only for leftovers of an already removed program', 'Buscar solo restos de un programa ya eliminado', 'Rechercher uniquement les résidus dʼun programme déjà supprimé', 'Искать только остатки уже удалённой программы', 'Önceden kaldırılmış bir programın yalnızca kalıntılarını ara')
    Main5                = @('Trockenlauf: prüfen, aber nichts verändern', 'Dry run: check without changing anything', 'Simulación: comprobar sin modificar nada', 'Simulation : vérifier sans rien modifier', 'Пробный запуск: проверить без изменений', 'Deneme çalışması: hiçbir şeyi değiştirmeden kontrol et')
    Main6                = @('Entfernungshistorie ansehen', 'View removal history', 'Ver historial de eliminaciones', 'Afficher lʼhistorique des suppressions', 'Просмотреть историю удалений', 'Kaldırma geçmişini görüntüle')
    Main7                = @('Von der Anwendung erstellte Logs löschen', 'Delete logs created by the application', 'Eliminar los registros creados por la aplicación', 'Supprimer les journaux créés par lʼapplication', 'Удалить журналы, созданные приложением', 'Uygulamanın oluşturduğu günlükleri sil')
    Main8                = @('Sprache ändern', 'Change language', 'Cambiar idioma', 'Changer de langue', 'Изменить язык', 'Dili değiştir')
    Main9                = @('Erweiterte Windows-Werkzeuge', 'Advanced Windows tools', 'Herramientas avanzadas de Windows', 'Outils Windows avancés', 'Расширенные инструменты Windows', 'Gelişmiş Windows araçları')
    Main0                = @('Programm beenden', 'Exit application', 'Salir de la aplicación', 'Quitter lʼapplication', 'Выйти из приложения', 'Uygulamadan çık')
    InvalidMain          = @('Bitte eine Zahl von 0 bis 9 eingeben.', 'Please enter a number from 0 to 9.', 'Introduce un número del 0 al 9.', 'Veuillez saisir un nombre de 0 à 9.', 'Введите число от 0 до 9.', 'Lütfen 0 ile 9 arasında bir sayı girin.')
    InstalledTitle      = @('Installierte Anwendungen', 'Installed applications', 'Aplicaciones instaladas', 'Applications installées', 'Установленные приложения', 'Yüklü uygulamalar')
    FoundProgramsTitle   = @('Gefundene Programme', 'Matching programs', 'Programas encontrados', 'Programmes trouvés', 'Найденные программы', 'Bulunan programlar')
    AllAppsTitle         = @('Alle Anwendungen und Systemkomponenten', 'All applications and system components', 'Todas las aplicaciones y componentes del sistema', 'Toutes les applications et composants système', 'Все приложения и системные компоненты', 'Tüm uygulamalar ve sistem bileşenleri')
    NoApps               = @('In dieser Ansicht wurden keine passenden Anwendungen gefunden.', 'No matching applications were found in this view.', 'No se encontraron aplicaciones coincidentes en esta vista.', 'Aucune application correspondante nʼa été trouvée dans cette vue.', 'В этом представлении подходящие приложения не найдены.', 'Bu görünümde eşleşen uygulama bulunamadı.')
    FilterLabel          = @('Filter: {0}', 'Filter: {0}', 'Filtro: {0}', 'Filtre : {0}', 'Фильтр: {0}', 'Filtre: {0}')
    PageLabel            = @('Seite {0} von {1} | Einträge: {2}', 'Page {0} of {1} | Entries: {2}', 'Página {0} de {1} | Entradas: {2}', 'Page {0} sur {1} | Entrées : {2}', 'Страница {0} из {1} | Записей: {2}', 'Sayfa {0}/{1} | Kayıt: {2}')
    NoFilterHits         = @('Keine Treffer für diesen Filter.', 'No matches for this filter.', 'No hay resultados para este filtro.', 'Aucun résultat pour ce filtre.', 'Нет результатов для этого фильтра.', 'Bu filtre için sonuç yok.')
    ProtectedLabel       = @('geschützt', 'protected', 'protegido', 'protégé', 'защищено', 'korumalı')
    ListCommands         = @('Befehle: positive Nummer = auswählen | 0 beenden | -1 weiter | -2 zurück | -3 suchen | -4 Filter löschen | -5 Hauptmenü', 'Commands: positive number = select | 0 exit | -1 next | -2 previous | -3 search | -4 clear filter | -5 main menu', 'Comandos: número positivo = seleccionar | 0 salir | -1 siguiente | -2 anterior | -3 buscar | -4 borrar filtro | -5 menú principal', 'Commandes : nombre positif = sélectionner | 0 quitter | -1 suivant | -2 précédent | -3 rechercher | -4 effacer le filtre | -5 menu principal', 'Команды: положительный номер = выбрать | 0 выход | -1 далее | -2 назад | -3 поиск | -4 сбросить фильтр | -5 главное меню', 'Komutlar: pozitif sayı = seç | 0 çıkış | -1 ileri | -2 geri | -3 ara | -4 filtreyi temizle | -5 ana menü')
    InvalidList          = @('Bitte eine angezeigte Nummer oder einen der nummerierten Befehle eingeben.', 'Enter a displayed number or one of the numbered commands.', 'Introduce un número mostrado o uno de los comandos numerados.', 'Saisissez un numéro affiché ou lʼune des commandes numérotées.', 'Введите показанный номер или одну из пронумерованных команд.', 'Gösterilen bir numarayı veya numaralı komutlardan birini girin.')
    ProtectedItem        = @('Dieser Eintrag ist durch Windows geschützt oder besitzt kein Deinstallationskommando.', 'This entry is protected by Windows or has no uninstall command.', 'Esta entrada está protegida por Windows o no tiene comando de desinstalación.', 'Cette entrée est protégée par Windows ou ne possède aucune commande de désinstallation.', 'Эта запись защищена Windows или не содержит команды удаления.', 'Bu kayıt Windows tarafından korunuyor veya kaldırma komutu yok.')
    Press1Back           = @('[1] Zurück | [0] Programm beenden', '[1] Back | [0] Exit application', '[1] Volver | [0] Salir', '[1] Retour | [0] Quitter', '[1] Назад | [0] Выйти', '[1] Geri | [0] Çıkış')
    OperationDone        = @('Vorgang abgeschlossen.', 'Operation completed.', 'Operación completada.', 'Opération terminée.', 'Операция завершена.', 'İşlem tamamlandı.')
    BackProgramList      = @('Zurück zur Programmliste', 'Return to program list', 'Volver a la lista de programas', 'Retour à la liste des programmes', 'Вернуться к списку программ', 'Program listesine dön')
    OpenRunLog           = @('Protokoll öffnen', 'Open log', 'Abrir registro', 'Ouvrir le journal', 'Открыть журнал', 'Günlüğü aç')
    RunDetails           = @('Ergebnis dieses Durchlaufs:', 'Results for this run:', 'Resultados de esta operación:', 'Résultats de cette opération :', 'Результаты этого запуска:', 'Bu çalıştırmanın sonuçları:')
    BackMain             = @('Zurück zum Hauptmenü', 'Return to main menu', 'Volver al menú principal', 'Retour au menu principal', 'Вернуться в главное меню', 'Ana menüye dön')
    InvalidPost          = @('Hier sind nur [1] und [0] gültig, wie oben beschriftet. Für eine andere Funktion [1] wählen, zur vorherigen Auswahl zurückkehren und dort die Funktionsnummer eingeben.', 'Only [1] and [0] are valid here, as labelled above. To run another feature, choose [1] to return to the previous menu, then enter its number there.', 'Aquí solo son válidos [1] y [0], tal como se indican arriba. Para usar otra función, elige [1] para volver al menú anterior y luego introduce allí su número.', 'Ici, seuls [1] et [0] sont valides, selon les libellés ci-dessus. Pour utiliser une autre fonction, choisissez [1] pour revenir au menu précédent, puis saisissez son numéro.', 'Здесь доступны только [1] и [0], как указано выше. Чтобы запустить другую функцию, нажмите [1] для возврата в предыдущее меню, затем введите её номер.', 'Burada yukarıda belirtildiği gibi yalnızca [1] ve [0] geçerlidir. Başka bir özellik için [1] ile önceki menüye dönüp numarasını girin.')
    BackPreviousMenu     = @('Zurück zur vorherigen Auswahl', 'Back to the previous menu', 'Volver al menú anterior', 'Retour au menu précédent', 'Вернуться в предыдущее меню', 'Önceki menüye dön')
    InvalidAfterOperation = @('Hier sind [1] Hauptmenü, [2] Programmliste, [3] Protokoll öffnen und [0] Beenden gültig.', 'Valid choices are [1] main menu, [2] program list, [3] open log, and [0] exit.', 'Las opciones válidas son [1] menú principal, [2] lista de programas, [3] abrir registro y [0] salir.', 'Les choix valides sont [1] menu principal, [2] liste des programmes, [3] ouvrir le journal et [0] quitter.', 'Допустимые варианты: [1] главное меню, [2] список программ, [3] открыть журнал, [0] выход.', 'Geçerli seçenekler: [1] ana menü, [2] program listesi, [3] günlüğü aç, [0] çıkış.')
    InvalidAfterOperationNoLog = @('Hier sind [1] Hauptmenü, [2] Programmliste und [0] Beenden gültig.', 'Valid choices are [1] main menu, [2] program list, and [0] exit.', 'Las opciones válidas son [1] menú principal, [2] lista de programas y [0] salir.', 'Les choix valides sont [1] menu principal, [2] liste des programmes et [0] quitter.', 'Допустимые варианты: [1] главное меню, [2] список программ, [0] выход.', 'Geçerli seçenekler: [1] ana menü, [2] program listesi, [0] çıkış.')
    InvalidAVChoice     = @('Bitte eine Zahl von 0 bis 7 eingeben.', 'Please enter a number from 0 to 7.', 'Introduce un número del 0 al 7.', 'Saisissez un nombre de 0 à 7.', 'Введите число от 0 до 7.', '0 ile 7 arasında bir sayı girin.')
    InvalidPrivacyChoice = @('Bitte 1, 2, 3 oder 0 eingeben.', 'Enter 1, 2, 3, or 0.', 'Introduce 1, 2, 3 o 0.', 'Saisissez 1, 2, 3 ou 0.', 'Введите 1, 2, 3 или 0.', '1, 2, 3 veya 0 girin.')
    InvalidStartupMenu  = @('Bitte [1], [2], [3] oder [0] wählen.', 'Choose [1], [2], [3], or [0].', 'Elige [1], [2], [3] o [0].', 'Choisissez [1], [2], [3] ou [0].', 'Выберите [1], [2], [3] или [0].', '[1], [2], [3] veya [0] seçin.')
    Selected             = @('Ausgewählt: {0}', 'Selected: {0}', 'Seleccionado: {0}', 'Sélectionné : {0}', 'Выбрано: {0}', 'Seçildi: {0}')
    RemovalWarning       = @('Die reguläre Deinstallation und alle oben aufgeführten Spuren werden entfernt.', 'The regular uninstall and all leftovers listed above will be removed.', 'Se eliminarán la desinstalación normal y todos los restos indicados.', 'La désinstallation normale et tous les résidus listés ci-dessus seront supprimés.', 'Будут выполнены обычное удаление и удаление всех перечисленных остатков.', 'Normal kaldırma ve yukarıda listelenen tüm kalıntılar silinecek.')
    PersonalWarning      = @('Auch gefundene persönliche Dateien werden endgültig gelöscht und landen nicht im Papierkorb.', 'Any personal files found will also be permanently deleted and will not go to the Recycle Bin.', 'Los archivos personales encontrados también se eliminarán definitivamente sin pasar por la Papelera.', 'Les fichiers personnels trouvés seront également supprimés définitivement sans passer par la Corbeille.', 'Найденные личные файлы также будут удалены без возможности восстановления и не попадут в корзину.', 'Bulunan kişisel dosyalar da kalıcı olarak silinecek ve Geri Dönüşüm Kutusuʼna gitmeyecek.')
    ConfirmStart         = @('Entfernung starten', 'Start removal', 'Iniciar eliminación', 'Démarrer la suppression', 'Начать удаление', 'Kaldırmayı başlat')
    ResidualSuffix       = @('{0} (nur Reste)', '{0} (leftovers only)', '{0} (solo restos)', '{0} (résidus uniquement)', '{0} (только остатки)', '{0} (yalnızca kalıntılar)')
    InvalidConfirm       = @('Bitte 1 zum Starten, 2 für das Hauptmenü oder 0 zum Beenden eingeben.', 'Enter 1 to start, 2 for the main menu, or 0 to exit.', 'Introduce 1 para iniciar, 2 para el menú principal o 0 para salir.', 'Saisissez 1 pour démarrer, 2 pour le menu principal ou 0 pour quitter.', 'Введите 1 для запуска, 2 для главного меню или 0 для выхода.', 'Başlatmak için 1, ana menü için 2 veya çıkmak için 0 girin.')
    HistoryHeading       = @('Letzte Entfernungen', 'Recent removals', 'Eliminaciones recientes', 'Suppressions récentes', 'Недавние удаления', 'Son kaldırmalar')
    HistoryTitle         = @('Entfernungshistorie', 'Removal history', 'Historial de eliminaciones', 'Historique des suppressions', 'История удалений', 'Kaldırma geçmişi')
    HistoryNone          = @('Noch keine Entfernungen gespeichert.', 'No removals have been recorded yet.', 'Aún no se han registrado eliminaciones.', 'Aucune suppression nʼa encore été enregistrée.', 'Удаления пока не записаны.', 'Henüz kaldırma kaydı yok.')
    HistoryLine          = @('{0} | {1} | entfernt: {2} | Status: {3}', '{0} | {1} | removed: {2} | status: {3}', '{0} | {1} | eliminados: {2} | estado: {3}', '{0} | {1} | supprimés : {2} | état : {3}', '{0} | {1} | удалено: {2} | статус: {3}', '{0} | {1} | kaldırılan: {2} | durum: {3}')
    HistoryFreed         = @(' | frei: {0}', ' | freed: {0}', ' | liberado: {0}', ' | libéré : {0}', ' | освобождено: {0}', ' | boşaltılan: {0}')
    StatusComplete       = @('vollständig', 'complete', 'completo', 'terminé', 'завершено', 'tamamlandı')
    StatusWarnings       = @('mit Hinweisen', 'with warnings', 'con avisos', 'avec avertissements', 'с предупреждениями', 'uyarılarla')
    LogsTitle            = @('Anwendungs-Logs löschen', 'Delete application logs', 'Eliminar registros de la aplicación', 'Supprimer les journaux de lʼapplication', 'Удалить журналы приложения', 'Uygulama günlüklerini sil')
    LogsCount            = @('Gefundene Logdateien: {0}', 'Log files found: {0}', 'Archivos de registro encontrados: {0}', 'Fichiers journaux trouvés : {0}', 'Найдено файлов журналов: {0}', 'Bulunan günlük dosyası: {0}')
    LogsDelete           = @('Alle angezeigten Logs löschen', 'Delete all displayed logs', 'Eliminar todos los registros mostrados', 'Supprimer tous les journaux affichés', 'Удалить все показанные журналы', 'Gösterilen tüm günlükleri sil')
    LogsDeleted          = @('Logdateien gelöscht: {0}', 'Log files deleted: {0}', 'Archivos de registro eliminados: {0}', 'Fichiers journaux supprimés : {0}', 'Удалено файлов журналов: {0}', 'Silinen günlük dosyası: {0}')
    LogsFailed           = @('Nicht gelöschte Logdateien: {0}', 'Log files not deleted: {0}', 'Archivos de registro no eliminados: {0}', 'Fichiers journaux non supprimés : {0}', 'Не удалено файлов журналов: {0}', 'Silinemeyen günlük dosyası: {0}')
    LogsNone             = @('Es sind keine von der Anwendung erstellten Logs vorhanden.', 'There are no logs created by the application.', 'No hay registros creados por la aplicación.', 'Aucun journal créé par lʼapplication nʼest présent.', 'Журналы, созданные приложением, отсутствуют.', 'Uygulamanın oluşturduğu günlük yok.')
    InvalidLogs          = @('Bitte 1 zum Löschen, 2 für das Hauptmenü oder 0 zum Beenden eingeben.', 'Enter 1 to delete, 2 for the main menu, or 0 to exit.', 'Introduce 1 para eliminar, 2 para el menú principal o 0 para salir.', 'Saisissez 1 pour supprimer, 2 pour le menu principal ou 0 pour quitter.', 'Введите 1 для удаления, 2 для главного меню или 0 для выхода.', 'Silmek için 1, ana menü için 2 veya çıkmak için 0 girin.')
    LanguageTitle        = @('Sprache ändern', 'Change language', 'Cambiar idioma', 'Changer de langue', 'Изменить язык', 'Dili değiştir')
    LanguageCurrent      = @('Aktuelle Sprache: {0}', 'Current language: {0}', 'Idioma actual: {0}', 'Langue actuelle : {0}', 'Текущий язык: {0}', 'Geçerli dil: {0}')
    LanguageSaved        = @('Sprache gespeichert: {0}', 'Language saved: {0}', 'Idioma guardado: {0}', 'Langue enregistrée : {0}', 'Язык сохранён: {0}', 'Dil kaydedildi: {0}')
    InvalidLanguage      = @('Bitte eine Zahl von 0 bis 6 eingeben.', 'Please enter a number from 0 to 6.', 'Introduce un número del 0 al 6.', 'Veuillez saisir un nombre de 0 à 6.', 'Введите число от 0 до 6.', 'Lütfen 0 ile 6 arasında bir sayı girin.')
    ProgramNamePrompt    = @('Programmname eingeben', 'Enter program name', 'Introduce el nombre del programa', 'Saisissez le nom du programme', 'Введите имя программы', 'Program adını girin')
    ResidualNamePrompt   = @('Name des bereits entfernten Programms', 'Name of the already removed program', 'Nombre del programa ya eliminado', 'Nom du programme déjà supprimé', 'Имя уже удалённой программы', 'Önceden kaldırılan programın adı')
    DryRunNamePrompt     = @('Programmname für den Trockenlauf', 'Program name for the dry run', 'Nombre del programa para la simulación', 'Nom du programme pour la simulation', 'Имя программы для пробного запуска', 'Deneme çalışması için program adı')
    ProgramEnded         = @('Programm beendet.', 'Application closed.', 'Aplicación cerrada.', 'Application fermée.', 'Приложение закрыто.', 'Uygulama kapatıldı.')
    NoName               = @('Kein Programmname angegeben. Es wurde nichts verändert.', 'No program name was entered. Nothing was changed.', 'No se indicó ningún programa. No se modificó nada.', 'Aucun nom de programme nʼa été saisi. Rien nʼa été modifié.', 'Имя программы не указано. Изменений нет.', 'Program adı girilmedi. Hiçbir şey değiştirilmedi.')
    ErrorPrefix          = @('Fehler: {0}', 'Error: {0}', 'Error: {0}', 'Erreur : {0}', 'Ошибка: {0}', 'Hata: {0}')
    ProgressPrepare      = @('Vorgang wird vorbereitet', 'Preparing operation', 'Preparando la operación', 'Préparation de lʼopération', 'Подготовка операции', 'İşlem hazırlanıyor')
    ProgressInventory    = @('Installierte Programme werden eingelesen', 'Reading installed programs', 'Leyendo los programas instalados', 'Lecture des programmes installés', 'Чтение установленных программ', 'Yüklü programlar okunuyor')
    ProgressIdentity     = @('Suchprofil wird erstellt', 'Creating search profile', 'Creando el perfil de búsqueda', 'Création du profil de recherche', 'Создание профиля поиска', 'Arama profili oluşturuluyor')
    ProgressSearch       = @('Lokale Spuren werden gesucht', 'Searching for local leftovers', 'Buscando restos locales', 'Recherche des résidus locaux', 'Поиск локальных остатков', 'Yerel kalıntılar aranıyor')
    ProgressPreview      = @('Vorschau ist vollständig', 'Preview is complete', 'Vista previa completada', 'Aperçu terminé', 'Предварительный просмотр готов', 'Önizleme tamamlandı')
    ProgressDryDone      = @('Trockenlauf abgeschlossen', 'Dry run completed', 'Simulación completada', 'Simulation terminée', 'Пробный запуск завершён', 'Deneme çalışması tamamlandı')
    ProgressDone         = @('Vorgang abgeschlossen', 'Operation completed', 'Operación completada', 'Opération terminée', 'Операция завершена', 'İşlem tamamlandı')
    ProgressRecheck      = @('Ausgewählte Anwendung wird erneut geprüft', 'Rechecking selected application', 'Comprobando de nuevo la aplicación seleccionada', 'Nouvelle vérification de lʼapplication sélectionnée', 'Повторная проверка выбранного приложения', 'Seçilen uygulama yeniden denetleniyor')
    ProgressBackup       = @('Sicherung wird vorbereitet', 'Preparing backup', 'Preparando la copia de seguridad', 'Préparation de la sauvegarde', 'Подготовка резервной копии', 'Yedekleme hazırlanıyor')
    ProgressUninstall    = @('Offizielle Deinstallation läuft', 'Official uninstall is running', 'La desinstalación oficial está en curso', 'La désinstallation officielle est en cours', 'Выполняется официальное удаление', 'Resmî kaldırma çalışıyor')
    ProgressUninstallDone= @('Reguläre Deinstallation abgeschlossen', 'Regular uninstall completed', 'Desinstalación normal completada', 'Désinstallation normale terminée', 'Обычное удаление завершено', 'Normal kaldırma tamamlandı')
    ProgressRescan       = @('Verbliebene Spuren werden gesucht', 'Searching for remaining leftovers', 'Buscando restos restantes', 'Recherche des résidus restants', 'Поиск оставшихся следов', 'Kalan kalıntılar aranıyor')
    ProgressRescanDone   = @('Nachsuche abgeschlossen', 'Follow-up scan completed', 'Búsqueda posterior completada', 'Analyse complémentaire terminée', 'Повторный поиск завершён', 'Son tarama tamamlandı')
    ProgressRemove       = @('Gefundene Spuren werden entfernt', 'Removing found leftovers', 'Eliminando los restos encontrados', 'Suppression des résidus trouvés', 'Удаление найденных остатков', 'Bulunan kalıntılar kaldırılıyor')
    ProgressCleanupDone  = @('Bereinigung abgeschlossen', 'Cleanup completed', 'Limpieza completada', 'Nettoyage terminé', 'Очистка завершена', 'Temizleme tamamlandı')
    ProgressVerify       = @('Abschlussprüfung läuft', 'Running final verification', 'Ejecutando la comprobación final', 'Vérification finale en cours', 'Выполняется итоговая проверка', 'Son doğrulama çalışıyor')
    AdminRequired        = @('Für die Entfernung werden Administratorrechte benötigt. Im Testmodus wurde keine UAC-Abfrage geöffnet.', 'Administrator rights are required for removal. No UAC prompt was opened in test mode.', 'Se requieren derechos de administrador. En modo de prueba no se abrió UAC.', 'Des droits administrateur sont requis. Aucune demande UAC nʼa été ouverte en mode test.', 'Для удаления нужны права администратора. В тестовом режиме запрос UAC не открывался.', 'Kaldırma için yönetici hakları gerekir. Test modunda UAC açılmadı.')
    UacOpening           = @('Jetzt wird die einmalige Windows-Administratorabfrage für die Entfernung geöffnet.', 'The one-time Windows administrator prompt will now open for removal.', 'Ahora se abrirá una única solicitud de administrador de Windows.', 'La demande administrateur Windows unique va maintenant sʼouvrir.', 'Сейчас откроется однократный запрос прав администратора Windows.', 'Kaldırma için tek seferlik Windows yönetici isteği şimdi açılacak.')
    UacCancelled         = @('Die Administratorabfrage wurde abgebrochen. Es wurde nichts entfernt.', 'The administrator prompt was cancelled. Nothing was removed.', 'Se canceló la solicitud de administrador. No se eliminó nada.', 'La demande administrateur a été annulée. Rien nʼa été supprimé.', 'Запрос прав администратора отменён. Ничего не удалено.', 'Yönetici isteği iptal edildi. Hiçbir şey kaldırılmadı.')
    InventoryReading     = @('Installierte Anwendungen werden eingelesen.', 'Reading installed applications.', 'Leyendo las aplicaciones instaladas.', 'Lecture des applications installées.', 'Чтение установленных приложений.', 'Yüklü uygulamalar okunuyor.')
    InventoryAllReading  = @('Alle installierten Einträge werden eingelesen.', 'Reading all installed entries.', 'Leyendo todas las entradas instaladas.', 'Lecture de toutes les entrées installées.', 'Чтение всех установленных записей.', 'Tüm yüklü kayıtlar okunuyor.')
    SelectionCancelled   = @('Auswahl abgebrochen. Es wurde nichts verändert.', 'Selection cancelled. Nothing was changed.', 'Selección cancelada. No se modificó nada.', 'Sélection annulée. Rien nʼa été modifié.', 'Выбор отменён. Изменений нет.', 'Seçim iptal edildi. Hiçbir şey değiştirilmedi.')
    NoProgramFound       = @('Kein installiertes Programm passend zu "{0}" gefunden.', 'No installed program matching "{0}" was found.', 'No se encontró ningún programa instalado que coincida con «{0}».', 'Aucun programme installé correspondant à « {0} » nʼa été trouvé.', 'Установленная программа, соответствующая «{0}», не найдена.', '"{0}" ile eşleşen yüklü program bulunamadı.')
    ResidualQuestion     = @('Nur nach Resten dieses Namens suchen?', 'Search only for leftovers with this name?', '¿Buscar solo restos con este nombre?', 'Rechercher uniquement les résidus portant ce nom ?', 'Искать только остатки с этим именем?', 'Yalnızca bu ada sahip kalıntılar aransın mı?')
    YesResidual          = @('Ja, Reste suchen', 'Yes, search for leftovers', 'Sí, buscar restos', 'Oui, rechercher les résidus', 'Да, искать остатки', 'Evet, kalıntıları ara')
    SafeTerms            = @('Sichere Suchbegriffe: {0}', 'Safe search terms: {0}', 'Términos de búsqueda seguros: {0}', 'Termes de recherche sûrs : {0}', 'Безопасные поисковые термины: {0}', 'Güvenli arama terimleri: {0}')
    DeepSearch           = @('Programmreste werden gesucht. Die tiefe Registry-Suche kann einige Minuten dauern.', 'Searching for program leftovers. The deep registry scan can take several minutes.', 'Buscando restos del programa. El análisis profundo del registro puede tardar varios minutos.', 'Recherche des résidus. Lʼanalyse approfondie du registre peut prendre plusieurs minutes.', 'Идёт поиск остатков программы. Глубокая проверка реестра может занять несколько минут.', 'Program kalıntıları aranıyor. Ayrıntılı kayıt defteri taraması birkaç dakika sürebilir.')
    DryRunDone           = @('Trockenlauf beendet. Es wurde nichts verändert.', 'Dry run completed. Nothing was changed.', 'Simulación terminada. No se modificó nada.', 'Simulation terminée. Rien nʼa été modifié.', 'Пробный запуск завершён. Изменений нет.', 'Deneme çalışması tamamlandı. Hiçbir şey değiştirilmedi.')
    LogLabel             = @('Protokoll: {0}', 'Log: {0}', 'Registro: {0}', 'Journal : {0}', 'Журнал: {0}', 'Günlük: {0}')
    RescanMessage        = @('Verbleibende Spuren werden erneut geprüft.', 'Remaining leftovers are being checked again.', 'Se vuelven a comprobar los restos restantes.', 'Les résidus restants sont vérifiés à nouveau.', 'Оставшиеся следы проверяются повторно.', 'Kalan kalıntılar yeniden denetleniyor.')
    RemovedCount         = @('Entfernte Spuren: {0}', 'Removed leftovers: {0}', 'Restos eliminados: {0}', 'Résidus supprimés : {0}', 'Удалено следов: {0}', 'Kaldırılan kalıntı: {0}')
    FailedCount          = @('Nicht entfernte Spuren: {0}', 'Leftovers not removed: {0}', 'Restos no eliminados: {0}', 'Résidus non supprimés : {0}', 'Не удалено следов: {0}', 'Kaldırılamayan kalıntı: {0}')
    FinalCheck           = @('Abschlussprüfung läuft.', 'Final verification is running.', 'La comprobación final está en curso.', 'La vérification finale est en cours.', 'Выполняется итоговая проверка.', 'Son doğrulama çalışıyor.')
    FinishedClean        = @('Fertig: Es wurden keine weiteren passenden lokalen Spuren gefunden.', 'Done: No further matching local leftovers were found.', 'Listo: no se encontraron más restos locales coincidentes.', 'Terminé : aucun autre résidu local correspondant nʼa été trouvé.', 'Готово: других подходящих локальных следов не найдено.', 'Bitti: Eşleşen başka yerel kalıntı bulunamadı.')
    FinishedRemaining    = @('Fertig mit Resthinweis: Die Kontrolle fand noch {0} Treffer.', 'Done with a leftovers notice: Verification found {0} remaining matches.', 'Finalizado con aviso: la comprobación encontró {0} coincidencias restantes.', 'Terminé avec avertissement : la vérification a trouvé {0} correspondances restantes.', 'Завершено с предупреждением: найдено ещё {0} совпадений.', 'Kalıntı uyarısıyla tamamlandı: Doğrulama {0} eşleşme daha buldu.')
    RestartNotice        = @('Windows verlangt einen Neustart, damit die Entfernung vollständig abgeschlossen wird.', 'Windows requires a restart to complete the removal.', 'Windows requiere un reinicio para completar la eliminación.', 'Windows nécessite un redémarrage pour terminer la suppression.', 'Для завершения удаления Windows требуется перезагрузка.', 'Kaldırmayı tamamlamak için Windows yeniden başlatılmalıdır.')
    StoreReadError       = @('Microsoft-Store-Apps konnten nicht vollständig gelesen werden: {0}', 'Microsoft Store apps could not be read completely: {0}', 'No se pudieron leer completamente las aplicaciones de Microsoft Store: {0}', 'Les applications Microsoft Store nʼont pas pu être lues entièrement : {0}', 'Не удалось полностью прочитать приложения Microsoft Store: {0}', 'Microsoft Store uygulamaları tam olarak okunamadı: {0}')
    SafetyParent         = @('Sicherheitsgrenze: Übergeordnetes Verzeichnis wird nicht vorgemerkt: {0}', 'Safety limit: Parent directory will not be queued: {0}', 'Límite de seguridad: no se incluirá el directorio superior: {0}', 'Limite de sécurité : le dossier parent ne sera pas sélectionné : {0}', 'Ограничение безопасности: родительская папка не будет добавлена: {0}', 'Güvenlik sınırı: Üst dizin sıraya alınmayacak: {0}')
    SafetyLink           = @('Verknüpftes Dateisystemziel wird aus Sicherheitsgründen übersprungen: {0}', 'Linked file-system target is skipped for safety: {0}', 'Se omite por seguridad el destino enlazado: {0}', 'La cible liée est ignorée pour des raisons de sécurité : {0}', 'Связанная цель файловой системы пропущена из соображений безопасности: {0}', 'Bağlı dosya sistemi hedefi güvenlik nedeniyle atlanıyor: {0}')
    PathCheckError       = @('Pfad konnte nicht geprüft werden: {0}', 'Path could not be checked: {0}', 'No se pudo comprobar la ruta: {0}', 'Le chemin nʼa pas pu être vérifié : {0}', 'Не удалось проверить путь: {0}', 'Yol denetlenemedi: {0}')
    ServicesReadError    = @('Dienste konnten nicht vollständig geprüft werden: {0}', 'Services could not be checked completely: {0}', 'No se pudieron comprobar completamente los servicios: {0}', 'Les services nʼont pas pu être vérifiés entièrement : {0}', 'Не удалось полностью проверить службы: {0}', 'Hizmetler tam olarak denetlenemedi: {0}')
    TasksReadError       = @('Geplante Aufgaben konnten nicht vollständig geprüft werden: {0}', 'Scheduled tasks could not be checked completely: {0}', 'No se pudieron comprobar completamente las tareas programadas: {0}', 'Les tâches planifiées nʼont pas pu être vérifiées entièrement : {0}', 'Не удалось полностью проверить запланированные задачи: {0}', 'Zamanlanmış görevler tam olarak denetlenemedi: {0}')
    NoTraces             = @('Keine zusätzlichen Spuren gefunden.', 'No additional leftovers found.', 'No se encontraron restos adicionales.', 'Aucun résidu supplémentaire trouvé.', 'Дополнительные следы не найдены.', 'Ek kalıntı bulunamadı.')
    TracesFound          = @('Gefundene Spuren: {0}', 'Leftovers found: {0}', 'Restos encontrados: {0}', 'Résidus trouvés : {0}', 'Найдено следов: {0}', 'Bulunan kalıntı: {0}')
    MoreItems            = @('... und {0} weitere', '... and {0} more', '... y {0} más', '... et {0} autres', '... и ещё {0}', '... ve {0} tane daha')
    PersonalFile         = @('persönliche Datei', 'personal file', 'archivo personal', 'fichier personnel', 'личный файл', 'kişisel dosya')
    RestorePointDone     = @('Windows-Wiederherstellungspunkt wurde erstellt.', 'Windows restore point was created.', 'Se creó un punto de restauración de Windows.', 'Un point de restauration Windows a été créé.', 'Точка восстановления Windows создана.', 'Windows geri yükleme noktası oluşturuldu.')
    RestorePointFailed   = @('Kein Wiederherstellungspunkt möglich. Die Systemwiederherstellung ist wahrscheinlich deaktiviert; persönliche Dateien wären davon ohnehin nicht umfasst.', 'A restore point could not be created. System Restore is probably disabled; personal files would not be covered anyway.', 'No se pudo crear un punto de restauración. Probablemente Restaurar sistema esté desactivado; los archivos personales no estarían incluidos.', 'Impossible de créer un point de restauration. La restauration du système est probablement désactivée ; les fichiers personnels ne seraient de toute façon pas couverts.', 'Не удалось создать точку восстановления. Вероятно, восстановление системы отключено; личные файлы всё равно не входят в неё.', 'Geri yükleme noktası oluşturulamadı. Sistem Geri Yükleme muhtemelen devre dışı; kişisel dosyalar zaten buna dahil değildir.')
    StoreRemoving        = @('Microsoft-Store-App wird entfernt: {0}', 'Removing Microsoft Store app: {0}', 'Eliminando la aplicación de Microsoft Store: {0}', 'Suppression de lʼapplication Microsoft Store : {0}', 'Удаление приложения Microsoft Store: {0}', 'Microsoft Store uygulaması kaldırılıyor: {0}')
    UninstallRunning     = @('Deinstallation läuft: {0}', 'Uninstalling: {0}', 'Desinstalando: {0}', 'Désinstallation en cours : {0}', 'Выполняется удаление: {0}', 'Kaldırılıyor: {0}')
    UninstallDone        = @('Die reguläre Deinstallation wurde abgeschlossen.', 'The regular uninstall was completed.', 'La desinstalación normal se completó.', 'La désinstallation normale est terminée.', 'Обычное удаление завершено.', 'Normal kaldırma tamamlandı.')
    LogSaveError         = @('Protokoll konnte nicht gespeichert werden: {0}', 'Log could not be saved: {0}', 'No se pudo guardar el registro: {0}', 'Le journal nʼa pas pu être enregistré : {0}', 'Не удалось сохранить журнал: {0}', 'Günlük kaydedilemedi: {0}')
    HistorySaveError     = @('Historie konnte nicht gespeichert werden: {0}', 'History could not be saved: {0}', 'No se pudo guardar el historial: {0}', 'Lʼhistorique nʼa pas pu être enregistré : {0}', 'Не удалось сохранить историю: {0}', 'Geçmiş kaydedilemedi: {0}')
    ToolsTitle           = @('Erweiterte Windows-Werkzeuge', 'Advanced Windows tools', 'Herramientas avanzadas de Windows', 'Outils Windows avancés', 'Расширенные инструменты Windows', 'Gelişmiş Windows araçları')
    Tools1               = @('Systemintegrität prüfen', 'Check system integrity', 'Comprobar la integridad del sistema', 'Vérifier lʼintégrité du système', 'Проверить целостность системы', 'Sistem bütünlüğünü denetle')
    Tools2               = @('AppX/UWP-Apps verwalten', 'Manage AppX/UWP apps', 'Administrar aplicaciones AppX/UWP', 'Gérer les applications AppX/UWP', 'Управление приложениями AppX/UWP', 'AppX/UWP uygulamalarını yönet')
    Tools3               = @('Verwaiste Registry-Einträge suchen', 'Scan for orphaned registry entries', 'Buscar entradas de registro huérfanas', 'Rechercher les entrées de registre orphelines', 'Поиск осиротевших записей реестра', 'Sahipsiz kayıt defteri girdilerini tara')
    Tools4               = @('Optionale Windows-Features verwalten', 'Manage optional Windows features', 'Administrar características opcionales de Windows', 'Gérer les fonctionnalités Windows facultatives', 'Управление дополнительными компонентами Windows', 'İsteğe bağlı Windows özelliklerini yönet')
    Tools5               = @('Systemoptimierung und Datenschutz', 'System optimization and privacy', 'Optimización del sistema y privacidad', 'Optimisation du système et confidentialité', 'Оптимизация системы и конфиденциальность', 'Sistem optimizasyonu ve gizlilik')
    Tools6               = @('ClamAV-Malware-Prüfung', 'ClamAV malware scan', 'Análisis antimalware ClamAV', 'Analyse antimalware ClamAV', 'Проверка на вредоносные программы ClamAV', 'ClamAV kötü amaçlı yazılım taraması')
    InvalidTools         = @('Bitte eine Zahl von 0 bis 6 eingeben.', 'Please enter a number from 0 to 6.', 'Introduce un número del 0 al 6.', 'Veuillez saisir un nombre de 0 à 6.', 'Введите число от 0 до 6.', 'Lütfen 0 ile 6 arasında bir sayı girin.')
    AVTitle              = @('ClamAV-Malware-Prüfung', 'ClamAV malware scan', 'Análisis antimalware ClamAV', 'Analyse antimalware ClamAV', 'Проверка ClamAV', 'ClamAV kötü amaçlı yazılım taraması')
    AVReturnMenu         = @('ClamAV-Menü öffnen (dort [3] = ClamAV-Engine aktualisieren)', 'Return to the ClamAV menu (there, [3] updates the ClamAV engine)', 'Volver al menú de ClamAV (allí, [3] actualiza el motor)', 'Retour au menu ClamAV (où [3] met à jour le moteur)', 'Вернуться в меню ClamAV (там [3] обновляет движок)', 'ClamAV menüsüne dön ([3] motoru günceller)')
    AV1                  = @('Status anzeigen', 'Show status', 'Mostrar estado', 'Afficher lʼétat', 'Показать состояние', 'Durumu göster')
    AV2                  = @('Portable ClamAV-Engine einrichten', 'Set up portable ClamAV engine', 'Configurar el motor portátil de ClamAV', 'Configurer le moteur portable ClamAV', 'Настроить портативный движок ClamAV', 'Taşınabilir ClamAV motorunu kur')
    AV3                  = @('ClamAV-Engine aktualisieren', 'Update ClamAV engine', 'Actualizar el motor de ClamAV', 'Mettre à jour le moteur ClamAV', 'Обновить движок ClamAV', 'ClamAV motorunu güncelle')
    AV4                  = @('Virensignaturen aktualisieren', 'Update virus signatures', 'Actualizar firmas de virus', 'Mettre à jour les signatures antivirus', 'Обновить вирусные сигнатуры', 'Virüs imzalarını güncelle')
    AV5                  = @('Schnellprüfung starten', 'Start quick scan', 'Iniciar análisis rápido', 'Lancer lʼanalyse rapide', 'Запустить быструю проверку', 'Hızlı taramayı başlat')
    AV6                  = @('Eigenen Pfad prüfen', 'Scan a custom path', 'Analizar una ruta', 'Analyser un chemin', 'Проверить выбранный путь', 'Özel bir yolu tara')
    AV7                  = @('Quarantäne anzeigen oder wiederherstellen', 'View or restore quarantine', 'Ver o restaurar la cuarentena', 'Afficher ou restaurer la quarantaine', 'Просмотр или восстановление карантина', 'Karantinayı görüntüle veya geri yükle')
    AVPathPrompt         = @('Zu prüfender Pfad', 'Path to scan', 'Ruta que se analizará', 'Chemin à analyser', 'Путь для проверки', 'Taranacak yol')
    AVNotAvailable      = @('Das Antivirus-Modul fehlt oder konnte nicht geladen werden: {0}', 'The antivirus module is missing or could not be loaded: {0}', 'Falta el módulo antivirus o no pudo cargarse: {0}', 'Le module antivirus est absent ou nʼa pas pu être chargé : {0}', 'Модуль антивируса отсутствует или не загружен: {0}', 'Antivirüs modülü eksik veya yüklenemedi: {0}')
    AVOptionalFailed     = @('Die optionale ClamAV-Prüfung konnte nicht abgeschlossen werden: {0}', 'The optional ClamAV scan could not be completed: {0}', 'No se pudo completar el análisis opcional de ClamAV: {0}', 'Lʼanalyse ClamAV facultative nʼa pas pu être terminée : {0}', 'Не удалось завершить дополнительную проверку ClamAV: {0}', 'İsteğe bağlı ClamAV taraması tamamlanamadı: {0}')
    AVFindings           = @('ClamAV-Funde: {0}. Es wurde nichts automatisch gelöscht.', 'ClamAV detections: {0}. Nothing was deleted automatically.', 'Detecciones de ClamAV: {0}. No se eliminó nada automáticamente.', 'Détections ClamAV : {0}. Rien nʼa été supprimé automatiquement.', 'Обнаружено ClamAV: {0}. Ничего не удалено автоматически.', 'ClamAV bulguları: {0}. Hiçbir şey otomatik silinmedi.')
    AVClean              = @('ClamAV-Prüfung ohne Fund abgeschlossen.', 'ClamAV scan completed without detections.', 'Análisis ClamAV completado sin detecciones.', 'Analyse ClamAV terminée sans détection.', 'Проверка ClamAV завершена без обнаружений.', 'ClamAV taraması bulgu olmadan tamamlandı.')
    AVNoQuarantine      = @('Keine aktiven Quarantäne-Einträge vorhanden.', 'No active quarantine entries exist.', 'No hay entradas de cuarentena activas.', 'Aucune entrée de quarantaine active.', 'Нет активных записей карантина.', 'Etkin karantina kaydı yok.')
    AVRestorePrompt      = @('Nummer zum Wiederherstellen oder 0 zum Zurückkehren', 'Number to restore or 0 to return', 'Número para restaurar o 0 para volver', 'Numéro à restaurer ou 0 pour revenir', 'Номер для восстановления или 0 для возврата', 'Geri yüklemek için numara veya dönmek için 0')
    ProtectedTitle       = @('GESCHÜTZTE WINDOWS-KOMPONENTE', 'PROTECTED WINDOWS COMPONENT', 'COMPONENTE PROTEGIDO DE WINDOWS', 'COMPOSANT WINDOWS PROTÉGÉ', 'ЗАЩИЩЁННЫЙ КОМПОНЕНТ WINDOWS', 'KORUNAN WINDOWS BİLEŞENİ')
    ProtectedReason      = @('Sperrliste: {0}. Ohne ausdrücklichen Override wird nichts entfernt.', 'Protection list: {0}. Nothing will be removed without an explicit override.', 'Lista de protección: {0}. No se eliminará nada sin una anulación explícita.', 'Liste de protection : {0}. Rien ne sera supprimé sans dérogation explicite.', 'Список защиты: {0}. Без явного переопределения ничего не будет удалено.', 'Koruma listesi: {0}. Açık bir geçersiz kılma olmadan hiçbir şey kaldırılmaz.')
    ProtectedAbort       = @('Abbrechen (empfohlen)', 'Cancel (recommended)', 'Cancelar (recomendado)', 'Annuler (recommandé)', 'Отмена (рекомендуется)', 'İptal (önerilen)')
    ProtectedOverride    = @('Override: trotzdem fortfahren', 'Override: continue anyway', 'Anular: continuar de todos modos', 'Dérogation : continuer quand même', 'Переопределить: всё равно продолжить', 'Geçersiz kıl: yine de devam et')
    InvalidProtected     = @('Bitte 1 zum Abbrechen oder 2 für den ausdrücklichen Override eingeben.', 'Enter 1 to cancel or 2 for the explicit override.', 'Introduce 1 para cancelar o 2 para la anulación explícita.', 'Saisissez 1 pour annuler ou 2 pour la dérogation explicite.', 'Введите 1 для отмены или 2 для явного переопределения.', 'İptal için 1 veya açık geçersiz kılma için 2 girin.')
    RestoreSkipped       = @('Wiederherstellungspunkt wurde per Override übersprungen.', 'Restore point was skipped by override.', 'El punto de restauración se omitió mediante anulación.', 'Le point de restauration a été ignoré par dérogation.', 'Точка восстановления пропущена переопределением.', 'Geri yükleme noktası geçersiz kılma ile atlandı.')
    RestoreBlocked       = @('Es konnte kein Wiederherstellungspunkt erstellt werden. Der Vorgang ist aus Sicherheitsgründen angehalten.', 'A restore point could not be created. The operation has been paused for safety.', 'No se pudo crear un punto de restauración. La operación se detuvo por seguridad.', 'Impossible de créer un point de restauration. Lʼopération est suspendue par sécurité.', 'Не удалось создать точку восстановления. Операция остановлена из соображений безопасности.', 'Geri yükleme noktası oluşturulamadı. İşlem güvenlik için durduruldu.')
    RestoreAbort         = @('Vorgang abbrechen (empfohlen)', 'Cancel operation (recommended)', 'Cancelar la operación (recomendado)', 'Annuler lʼopération (recommandé)', 'Отменить операцию (рекомендуется)', 'İşlemi iptal et (önerilen)')
    RestoreContinue      = @('Ohne Wiederherstellungspunkt fortfahren', 'Continue without a restore point', 'Continuar sin punto de restauración', 'Continuer sans point de restauration', 'Продолжить без точки восстановления', 'Geri yükleme noktası olmadan devam et')
    InvalidRestore       = @('Bitte 1 zum Abbrechen oder 2 zum ausdrücklichen Fortfahren eingeben.', 'Enter 1 to cancel or 2 to explicitly continue.', 'Introduce 1 para cancelar o 2 para continuar expresamente.', 'Saisissez 1 pour annuler ou 2 pour continuer explicitement.', 'Введите 1 для отмены или 2 для явного продолжения.', 'İptal için 1 veya açıkça devam etmek için 2 girin.')
    IntegrityTitle       = @('Systemintegritätsprüfung', 'System integrity check', 'Comprobación de integridad del sistema', 'Vérification de lʼintégrité du système', 'Проверка целостности системы', 'Sistem bütünlüğü denetimi')
    IntegrityQuestion    = @('Grundlegende Windows-Dienste jetzt prüfen?', 'Check essential Windows services now?', '¿Comprobar ahora los servicios esenciales de Windows?', 'Vérifier maintenant les services Windows essentiels ?', 'Проверить основные службы Windows сейчас?', 'Temel Windows hizmetleri şimdi denetlensin mi?')
    IntegrityRun         = @('Prüfung ausführen', 'Run check', 'Ejecutar comprobación', 'Exécuter la vérification', 'Запустить проверку', 'Denetimi çalıştır')
    IntegritySkip        = @('Prüfung überspringen', 'Skip check', 'Omitir comprobación', 'Ignorer la vérification', 'Пропустить проверку', 'Denetimi atla')
    IntegrityHealthy     = @('Integritätsprüfung ohne kritische Hinweise abgeschlossen.', 'Integrity check completed without critical findings.', 'Comprobación de integridad completada sin hallazgos críticos.', 'Vérification dʼintégrité terminée sans anomalie critique.', 'Проверка целостности завершена без критических замечаний.', 'Bütünlük denetimi kritik bulgu olmadan tamamlandı.')
    IntegrityWarnings    = @('Integritätsprüfung meldet {0} Hinweis(e). Details stehen im Log.', 'Integrity check reports {0} warning(s). Details are in the log.', 'La comprobación de integridad informa de {0} advertencia(s). Los detalles están en el registro.', 'La vérification dʼintégrité signale {0} avertissement(s). Détails dans le journal.', 'Проверка целостности обнаружила предупреждения: {0}. Подробности в журнале.', 'Bütünlük denetimi {0} uyarı bildirdi. Ayrıntılar günlükte.')
    IntegrityLine        = @('{0}: {1} | Starttyp: {2}', '{0}: {1} | startup: {2}', '{0}: {1} | inicio: {2}', '{0} : {1} | démarrage : {2}', '{0}: {1} | запуск: {2}', '{0}: {1} | başlangıç: {2}')
    AppxTitle            = @('AppX/UWP-Apps', 'AppX/UWP apps', 'Aplicaciones AppX/UWP', 'Applications AppX/UWP', 'Приложения AppX/UWP', 'AppX/UWP uygulamaları')
    AppxCurrentOnly      = @('Nur für den aktuellen Benutzer entfernen', 'Remove for current user only', 'Eliminar solo para el usuario actual', 'Supprimer uniquement pour lʼutilisateur actuel', 'Удалить только для текущего пользователя', 'Yalnızca geçerli kullanıcı için kaldır')
    AppxProvisioned     = @('Zusätzlich aus dem System-Image für neue Benutzer entfernen', 'Also remove from the system image for new users', 'Eliminar también de la imagen del sistema para nuevos usuarios', 'Supprimer aussi de lʼimage système pour les nouveaux utilisateurs', 'Также удалить из образа системы для новых пользователей', 'Yeni kullanıcılar için sistem imajından da kaldır')
    AppxProvisionedDone = @('Bereitgestellte AppX-Pakete aus dem System-Image entfernt: {0}', 'Provisioned AppX packages removed from the system image: {0}', 'Paquetes AppX aprovisionados eliminados de la imagen del sistema: {0}', 'Packages AppX provisionnés supprimés de lʼimage système : {0}', 'Подготовленных пакетов AppX удалено из образа системы: {0}', 'Sistem imajından kaldırılan sağlanmış AppX paketi: {0}')
    AppxScopeQuestion    = @('Geltungsbereich der AppX-Entfernung', 'Scope of AppX removal', 'Alcance de la eliminación AppX', 'Portée de la suppression AppX', 'Область удаления AppX', 'AppX kaldırma kapsamı')
    InvalidAppxScope     = @('Bitte 1, 2, 3 oder 0 eingeben.', 'Enter 1, 2, 3, or 0.', 'Introduce 1, 2, 3 o 0.', 'Saisissez 1, 2, 3 ou 0.', 'Введите 1, 2, 3 или 0.', '1, 2, 3 veya 0 girin.')
    OrphanTitle          = @('Verwaiste Deinstallationseinträge', 'Orphaned uninstall entries', 'Entradas de desinstalación huérfanas', 'Entrées de désinstallation orphelines', 'Осиротевшие записи удаления', 'Sahipsiz kaldırma girdileri')
    OrphanDescription    = @('Es werden nur verdächtige Uninstall-Einträge gezeigt, deren Programmdatei und Installationsordner fehlen.', 'Only suspicious uninstall entries with missing executable and install folder are shown.', 'Solo se muestran entradas sospechosas cuya aplicación y carpeta de instalación faltan.', 'Seules les entrées suspectes dont lʼexécutable et le dossier dʼinstallation manquent sont affichées.', 'Показываются только подозрительные записи без файла программы и папки установки.', 'Yalnızca program dosyası ve kurulum klasörü eksik şüpheli girdiler gösterilir.')
    OrphanNone           = @('Keine eindeutig verwaisten Einträge gefunden.', 'No clearly orphaned entries were found.', 'No se encontraron entradas claramente huérfanas.', 'Aucune entrée clairement orpheline trouvée.', 'Явно осиротевшие записи не найдены.', 'Açıkça sahipsiz girdi bulunamadı.')
    OrphanFound          = @('Verdächtige Einträge gefunden: {0}', 'Suspicious entries found: {0}', 'Entradas sospechosas encontradas: {0}', 'Entrées suspectes trouvées : {0}', 'Найдено подозрительных записей: {0}', 'Bulunan şüpheli girdi: {0}')
    OrphanDelete         = @('Ausgewählten Registry-Eintrag löschen', 'Delete selected registry entry', 'Eliminar la entrada de registro seleccionada', 'Supprimer lʼentrée de registre sélectionnée', 'Удалить выбранную запись реестра', 'Seçilen kayıt defteri girdisini sil')
    OrphanDeleted        = @('Registry-Eintrag wurde entfernt.', 'Registry entry was removed.', 'La entrada de registro fue eliminada.', 'Lʼentrée de registre a été supprimée.', 'Запись реестра удалена.', 'Kayıt defteri girdisi kaldırıldı.')
    FeatureTitle         = @('Aktivierte optionale Windows-Features', 'Enabled optional Windows features', 'Características opcionales de Windows activadas', 'Fonctionnalités Windows facultatives activées', 'Включённые дополнительные компоненты Windows', 'Etkin isteğe bağlı Windows özellikleri')
    FeatureNone          = @('Keine aktivierten optionalen Features gefunden oder DISM ist nicht verfügbar.', 'No enabled optional features were found or DISM is unavailable.', 'No se encontraron características activadas o DISM no está disponible.', 'Aucune fonctionnalité activée trouvée ou DISM indisponible.', 'Включённые компоненты не найдены или DISM недоступен.', 'Etkin özellik bulunamadı veya DISM kullanılamıyor.')
    FeatureWarning       = @('Das ausgewählte Windows-Feature wird deaktiviert: {0}', 'The selected Windows feature will be disabled: {0}', 'Se desactivará la característica de Windows seleccionada: {0}', 'La fonctionnalité Windows sélectionnée sera désactivée : {0}', 'Выбранный компонент Windows будет отключён: {0}', 'Seçilen Windows özelliği devre dışı bırakılacak: {0}')
    FeatureDisabled      = @('Windows-Feature deaktiviert: {0}', 'Windows feature disabled: {0}', 'Característica de Windows desactivada: {0}', 'Fonctionnalité Windows désactivée : {0}', 'Компонент Windows отключён: {0}', 'Windows özelliği devre dışı bırakıldı: {0}')
    PrivacyTitle         = @('Systemoptimierung und Datenschutz', 'System optimization and privacy', 'Optimización del sistema y privacidad', 'Optimisation du système et confidentialité', 'Оптимизация системы и конфиденциальность', 'Sistem optimizasyonu ve gizlilik')
    PrivacyDescription   = @('Vorschau: DiagTrack, Werbe-ID, Feedback, Cortana/Copilot, Bing-Suche und Consumer Features werden deaktiviert.', 'Preview: DiagTrack, advertising ID, feedback, Cortana/Copilot, Bing search and Consumer Features will be disabled.', 'Vista previa: se desactivarán DiagTrack, ID de publicidad, comentarios, Cortana/Copilot, búsqueda de Bing y Consumer Features.', 'Aperçu : DiagTrack, identifiant publicitaire, commentaires, Cortana/Copilot, recherche Bing et Consumer Features seront désactivés.', 'Предпросмотр: будут отключены DiagTrack, рекламный ID, отзывы, Cortana/Copilot, поиск Bing и Consumer Features.', 'Önizleme: DiagTrack, reklam kimliği, geri bildirim, Cortana/Copilot, Bing araması ve Consumer Features devre dışı bırakılacak.')
    PrivacyApply         = @('Angezeigte Datenschutz-Einstellungen anwenden', 'Apply the displayed privacy settings', 'Aplicar la configuración de privacidad mostrada', 'Appliquer les paramètres de confidentialité affichés', 'Применить показанные настройки конфиденциальности', 'Gösterilen gizlilik ayarlarını uygula')
    PrivacyRestore       = @('Von diesem Tool gesetzte Datenschutzwerte zurücksetzen', 'Reset privacy values set by this tool', 'Restablecer los valores de privacidad establecidos por esta herramienta', 'Réinitialiser les valeurs de confidentialité définies par cet outil', 'Сбросить параметры конфиденциальности, заданные этим инструментом', 'Bu araç tarafından ayarlanan gizlilik değerlerini sıfırla')
    PrivacyDone          = @('Datenschutz-Einstellungen wurden angewendet.', 'Privacy settings were applied.', 'Se aplicó la configuración de privacidad.', 'Les paramètres de confidentialité ont été appliqués.', 'Настройки конфиденциальности применены.', 'Gizlilik ayarları uygulandı.')
    PrivacyRestored      = @('Vom Tool gesetzte Datenschutzwerte wurden zurückgesetzt.', 'Privacy values set by the tool were reset.', 'Se restablecieron los valores de privacidad establecidos por la herramienta.', 'Les valeurs de confidentialité définies par lʼoutil ont été réinitialisées.', 'Параметры конфиденциальности инструмента сброшены.', 'Araç tarafından ayarlanan gizlilik değerleri sıfırlandı.')
    PrivacyNoBackup      = @('Es ist keine Datenschutz-Sicherung zum Zurücksetzen vorhanden.', 'No privacy backup is available to restore.', 'No hay una copia de seguridad de privacidad para restaurar.', 'Aucune sauvegarde de confidentialité nʼest disponible.', 'Нет резервной копии параметров конфиденциальности.', 'Geri yüklenecek gizlilik yedeği yok.')
    RegistryPathLabel    = @('Registry-Pfad: {0}', 'Registry path: {0}', 'Ruta del registro: {0}', 'Chemin du registre : {0}', 'Путь реестра: {0}', 'Kayıt defteri yolu: {0}')
    StorageFreed         = @('Gemessener freier Speicherplatz durch diesen Lauf: {0}', 'Measured free space gained in this run: {0}', 'Espacio libre medido ganado en esta ejecución: {0}', 'Espace libre mesuré gagné lors de cette exécution : {0}', 'Измеренное освобождённое место за этот запуск: {0}', 'Bu çalışmada ölçülen boş alan kazanımı: {0}')
    StorageUnclear       = @('Der freie Speicherplatz ist während des Laufs nicht gestiegen; parallele Systemaktivität kann die Messung beeinflussen.', 'Free space did not increase during the run; concurrent system activity can affect the measurement.', 'El espacio libre no aumentó; la actividad simultánea del sistema puede afectar la medición.', 'Lʼespace libre nʼa pas augmenté ; lʼactivité système simultanée peut influencer la mesure.', 'Свободное место не увеличилось; параллельная активность системы может повлиять на измерение.', 'Boş alan artmadı; eşzamanlı sistem etkinliği ölçümü etkileyebilir.')
    DeleteFoundTraces    = @('Alle oben angezeigten Datei- und Registry-Reste löschen', 'Delete all file and registry leftovers shown above', 'Eliminar todos los restos de archivos y registro mostrados', 'Supprimer tous les résidus de fichiers et de registre affichés', 'Удалить все показанные остатки файлов и реестра', 'Yukarıda gösterilen tüm dosya ve kayıt defteri kalıntılarını sil')
    KeepFoundTraces      = @('Reste behalten und Vorgang fortsetzen', 'Keep leftovers and continue', 'Conservar los restos y continuar', 'Conserver les résidus et continuer', 'Сохранить остатки и продолжить', 'Kalıntıları koru ve devam et')
    InvalidTraceDelete   = @('Bitte 1 zum Löschen oder 2 zum Behalten eingeben.', 'Enter 1 to delete or 2 to keep the leftovers.', 'Introduce 1 para eliminar o 2 para conservar los restos.', 'Saisissez 1 pour supprimer ou 2 pour conserver les résidus.', 'Введите 1 для удаления или 2 для сохранения остатков.', 'Silmek için 1 veya kalıntıları korumak için 2 girin.')
    InvalidOneTwo        = @('Bitte 1 oder 2 eingeben.', 'Enter 1 or 2.', 'Introduce 1 o 2.', 'Saisissez 1 ou 2.', 'Введите 1 или 2.', '1 veya 2 girin.')
}

# Neue REMNEXA-Arbeitsbereiche. Jede Zeichenfolge folgt der bestehenden
# Reihenfolge Deutsch, Englisch, Spanisch, Französisch, Russisch, Türkisch.
$script:Texts.BrandTagline = @('Entfernen. Prüfen. Neu beginnen.', 'Remove. Verify. Begin again.', 'Eliminar. Verificar. Empezar de nuevo.', 'Supprimer. Vérifier. Recommencer.', 'Удалить. Проверить. Начать заново.', 'Kaldır. Doğrula. Yeniden başla.')
$script:Texts.HomeTitle = @('Arbeitsbereich auswählen', 'Choose a workspace', 'Elegir un área de trabajo', 'Choisir un espace de travail', 'Выберите рабочий раздел', 'Çalışma alanı seçin')
$script:Texts.HomeDescription = @('Deinstallation, Antivirus, Autostart und Dienste sind voneinander getrennt.', 'Uninstall, antivirus, startup and services are separated.', 'Desinstalación, antivirus, inicio y servicios están separados.', 'Désinstallation, antivirus, démarrage et services sont séparés.', 'Удаление, антивирус, автозагрузка и службы разделены.', 'Kaldırma, antivirüs, başlangıç ve hizmetler birbirinden ayrıdır.')
$script:Texts.Home1 = @('Programme deinstallieren und Spuren bereinigen', 'Uninstall programs and clean leftovers', 'Desinstalar programas y limpiar restos', 'Désinstaller les programmes et nettoyer les résidus', 'Удалить программы и очистить остатки', 'Programları kaldır ve kalıntıları temizle')
$script:Texts.Home2 = @('Antivirus- und Malware-Prüfung mit ClamAV', 'Antivirus and malware scan with ClamAV', 'Análisis antivirus y antimalware con ClamAV', 'Analyse antivirus et antimalware avec ClamAV', 'Антивирусная проверка ClamAV', 'ClamAV ile antivirüs ve kötü amaçlı yazılım taraması')
$script:Texts.Home3 = @('Autostart-Programme verwalten', 'Manage startup programs', 'Administrar programas de inicio', 'Gérer les programmes de démarrage', 'Управление автозагрузкой', 'Başlangıç programlarını yönet')
$script:Texts.Home4 = @('Aktive Windows-Dienste anzeigen', 'Show active Windows services', 'Mostrar servicios activos de Windows', 'Afficher les services Windows actifs', 'Показать активные службы Windows', 'Etkin Windows hizmetlerini göster')
$script:Texts.Home5 = @('Entfernungshistorie ansehen', 'View removal history', 'Ver historial de eliminaciones', 'Afficher lʼhistorique des suppressions', 'Просмотреть историю удалений', 'Kaldırma geçmişini görüntüle')
$script:Texts.Home6 = @('Anwendungs-Logs verwalten', 'Manage application logs', 'Administrar registros de la aplicación', 'Gérer les journaux de lʼapplication', 'Управление журналами приложения', 'Uygulama günlüklerini yönet')
$script:Texts.Home7 = @('Sprache ändern', 'Change language', 'Cambiar idioma', 'Changer de langue', 'Изменить язык', 'Dili değiştir')
$script:Texts.Home8 = @('Erweiterte Windows-Werkzeuge', 'Advanced Windows tools', 'Herramientas avanzadas de Windows', 'Outils Windows avancés', 'Расширенные инструменты Windows', 'Gelişmiş Windows araçları')
$script:Texts.HomeInvalid = @('Bitte eine Zahl von 0 bis 8 eingeben.', 'Enter a number from 0 to 8.', 'Introduce un número del 0 al 8.', 'Saisissez un nombre de 0 à 8.', 'Введите число от 0 до 8.', '0 ile 8 arasında bir sayı girin.')
$script:Texts.BackHome = @('Zurück zur Startseite', 'Back to home', 'Volver al inicio', 'Retour à lʼaccueil', 'Вернуться на главную', 'Ana sayfaya dön')
$script:Texts.UninstallTitle = @('Deinstallation und Restebereinigung', 'Uninstall and leftover cleanup', 'Desinstalación y limpieza de restos', 'Désinstallation et nettoyage des résidus', 'Удаление и очистка остатков', 'Kaldırma ve kalıntı temizleme')

$script:Texts.StartupTitle = @('Autostart-Programme', 'Startup programs', 'Programas de inicio', 'Programmes de démarrage', 'Программы автозагрузки', 'Başlangıç programları')
$script:Texts.StartupDescription = @('Einträge werden nur deaktiviert und gesichert, nicht endgültig gelöscht.', 'Items are disabled and backed up, not permanently deleted.', 'Los elementos se desactivan y guardan, no se eliminan definitivamente.', 'Les éléments sont désactivés et sauvegardés, pas supprimés définitivement.', 'Элементы отключаются и сохраняются, а не удаляются навсегда.', 'Öğeler kalıcı silinmez; devre dışı bırakılır ve yedeklenir.')
$script:Texts.Startup1 = @('Aktive Autostart-Einträge auflisten und deaktivieren', 'List and disable active startup items', 'Listar y desactivar elementos de inicio activos', 'Lister et désactiver les éléments de démarrage actifs', 'Показать и отключить активные элементы', 'Etkin başlangıç öğelerini listele ve devre dışı bırak')
$script:Texts.Startup2 = @('Deaktivierten Eintrag wiederherstellen', 'Restore a disabled item', 'Restaurar un elemento desactivado', 'Restaurer un élément désactivé', 'Восстановить отключённый элемент', 'Devre dışı bırakılan öğeyi geri yükle')
$script:Texts.Startup3 = @('Autostart-Historie anzeigen', 'Show startup history', 'Mostrar historial de inicio', 'Afficher lʼhistorique du démarrage', 'Показать историю автозагрузки', 'Başlangıç geçmişini göster')
$script:Texts.StartupNone = @('Keine verwaltbaren aktiven Autostart-Einträge gefunden.', 'No manageable active startup items were found.', 'No se encontraron elementos de inicio activos administrables.', 'Aucun élément de démarrage actif gérable trouvé.', 'Управляемые активные элементы не найдены.', 'Yönetilebilir etkin başlangıç öğesi bulunamadı.')
$script:Texts.StartupBackupsNone = @('Keine deaktivierten Einträge zur Wiederherstellung vorhanden.', 'No disabled items are available to restore.', 'No hay elementos desactivados para restaurar.', 'Aucun élément désactivé à restaurer.', 'Нет отключённых элементов для восстановления.', 'Geri yüklenecek devre dışı öğe yok.')
$script:Texts.StartupHistoryNone = @('Noch keine Autostart-Änderungen gespeichert.', 'No startup changes have been recorded yet.', 'Aún no se han registrado cambios de inicio.', 'Aucune modification de démarrage enregistrée.', 'Изменения автозагрузки ещё не записаны.', 'Henüz başlangıç değişikliği kaydedilmedi.')
$script:Texts.StartupReadError = @('Autostart-Einträge konnten nicht vollständig gelesen werden: {0}', 'Startup items could not be read completely: {0}', 'No se pudieron leer completamente los elementos de inicio: {0}', 'Lecture incomplète des éléments de démarrage : {0}', 'Не удалось полностью прочитать автозагрузку: {0}', 'Başlangıç öğeleri tam okunamadı: {0}')
$script:Texts.StartupProtected = @('Dieser Windows-Systemeintrag wird aus Sicherheitsgründen nur angezeigt.', 'This Windows system item is shown read-only for safety.', 'Este elemento del sistema se muestra solo para lectura por seguridad.', 'Cet élément système est affiché en lecture seule par sécurité.', 'Этот системный элемент показан только для чтения.', 'Bu Windows sistem öğesi güvenlik için salt okunur gösterilir.')
$script:Texts.StartupConfirm = @('Autostart deaktivieren: {0}', 'Disable startup item: {0}', 'Desactivar elemento de inicio: {0}', 'Désactiver lʼélément de démarrage : {0}', 'Отключить автозагрузку: {0}', 'Başlangıç öğesini devre dışı bırak: {0}')
$script:Texts.StartupRestoreConfirm = @('Autostart wiederherstellen: {0}', 'Restore startup item: {0}', 'Restaurar elemento de inicio: {0}', 'Restaurer lʼélément de démarrage : {0}', 'Восстановить автозагрузку: {0}', 'Başlangıç öğesini geri yükle: {0}')
$script:Texts.StartupDisabled = @('Autostart wurde deaktiviert und gesichert: {0}', 'Startup item was disabled and backed up: {0}', 'El elemento de inicio fue desactivado y guardado: {0}', 'Lʼélément de démarrage a été désactivé et sauvegardé : {0}', 'Элемент автозагрузки отключён и сохранён: {0}', 'Başlangıç öğesi devre dışı bırakıldı ve yedeklendi: {0}')
$script:Texts.StartupRestored = @('Autostart wurde wiederhergestellt: {0}', 'Startup item was restored: {0}', 'El elemento de inicio fue restaurado: {0}', 'Lʼélément de démarrage a été restauré : {0}', 'Элемент автозагрузки восстановлен: {0}', 'Başlangıç öğesi geri yüklendi: {0}')
$script:Texts.StartupActionFailed = @('Autostart-Änderung fehlgeschlagen: {0}', 'Startup change failed: {0}', 'Error al cambiar el inicio: {0}', 'Échec de la modification du démarrage : {0}', 'Не удалось изменить автозагрузку: {0}', 'Başlangıç değişikliği başarısız: {0}')
$script:Texts.StartupSelect = @('Nummer des Eintrags auswählen; [0] zurück', 'Select an item number; [0] back', 'Selecciona un número; [0] volver', 'Sélectionnez un numéro ; [0] retour', 'Выберите номер; [0] назад', 'Öğe numarasını seçin; [0] geri')
$script:Texts.StartupInvalid = @('Bitte eine angezeigte Nummer oder 0 eingeben.', 'Enter a displayed number or 0.', 'Introduce un número mostrado o 0.', 'Saisissez un numéro affiché ou 0.', 'Введите показанный номер или 0.', 'Gösterilen bir numarayı veya 0 girin.')

$script:Texts.ServicesTitle = @('Aktive Windows-Dienste', 'Active Windows services', 'Servicios activos de Windows', 'Services Windows actifs', 'Активные службы Windows', 'Etkin Windows hizmetleri')
$script:Texts.ServicesDescription = @('Nur Anzeige: In diesem Bereich werden keine Dienste verändert.', 'Read-only: no services are changed in this workspace.', 'Solo lectura: no se modifica ningún servicio.', 'Lecture seule : aucun service nʼest modifié.', 'Только просмотр: службы не изменяются.', 'Salt okunur: bu alanda hizmetler değiştirilmez.')
$script:Texts.ServicesNone = @('Keine aktiven Dienste gefunden.', 'No active services were found.', 'No se encontraron servicios activos.', 'Aucun service actif trouvé.', 'Активные службы не найдены.', 'Etkin hizmet bulunamadı.')
$script:Texts.ServicesReadError = @('Dienste konnten nicht gelesen werden: {0}', 'Services could not be read: {0}', 'No se pudieron leer los servicios: {0}', 'Impossible de lire les services : {0}', 'Не удалось прочитать службы: {0}', 'Hizmetler okunamadı: {0}')
$script:Texts.ServicesCommands = @('[1] nächste Seite | [2] vorherige Seite | [3] suchen | [4] Filter löschen | [0] zurück', '[1] next page | [2] previous page | [3] search | [4] clear filter | [0] back', '[1] siguiente | [2] anterior | [3] buscar | [4] borrar filtro | [0] volver', '[1] suivant | [2] précédent | [3] rechercher | [4] effacer le filtre | [0] retour', '[1] далее | [2] назад | [3] поиск | [4] сбросить фильтр | [0] назад', '[1] ileri | [2] geri | [3] ara | [4] filtreyi temizle | [0] geri')
$script:Texts.ServicesPage = @('Seite {0} von {1} | aktive Dienste: {2}', 'Page {0} of {1} | active services: {2}', 'Página {0} de {1} | servicios activos: {2}', 'Page {0} sur {1} | services actifs : {2}', 'Страница {0} из {1} | активных служб: {2}', 'Sayfa {0}/{1} | etkin hizmet: {2}')

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowEmptyCollection()][object[]]$Values = @()
    )

    $index = [Array]::IndexOf($script:LanguageCodes, $script:Language)
    if ($index -lt 0) { $index = 0 }
    $translations = $script:Texts[$Key]
    if ($null -eq $translations) { return $Key }
    $text = [string]$translations[$index]
    if ([string]::IsNullOrWhiteSpace($text)) { $text = [string]$translations[0] }
    if ($Values.Count -gt 0) { return ($text -f $Values) }
    return $text
}

function Show-BrandHeader {
    param([AllowEmptyString()][string]$Section = '')

    try { $Host.UI.RawUI.WindowTitle = "$($script:BrandName) $($script:CleanerVersion)" } catch { }
    Write-Host '  .  :   ________' -ForegroundColor DarkCyan
    Write-Host ' .   :  /        \___' -ForegroundColor Cyan
    Write-Host '       \___   ____/  \____o' -ForegroundColor Cyan
    Write-Host '           \_/' -ForegroundColor DarkCyan
    Write-Host ('  {0}  {1}' -f $script:BrandName, $script:CleanerVersion) -ForegroundColor White
    Write-Host ('  ' + (T 'BrandTagline')) -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($Section)) {
        Write-Host ''
        Write-Host ('  ' + $Section) -ForegroundColor White
    }
    Write-Host ''
}

function Initialize-DataMigration {
    if ((Test-Path -LiteralPath $script:DataRoot) -or -not (Test-Path -LiteralPath $script:LegacyDataRoot)) { return }

    try {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        foreach ($name in @('Settings.json', 'History.jsonl', 'PrivacyBackup.json')) {
            $source = Join-Path $script:LegacyDataRoot $name
            $destination = Join-Path $script:DataRoot $name
            if ((Test-Path -LiteralPath $source) -and -not (Test-Path -LiteralPath $destination)) {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
        $legacyLogs = Join-Path $script:LegacyDataRoot 'Logs'
        if (Test-Path -LiteralPath $legacyLogs) {
            New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
            Copy-Item -Path (Join-Path $legacyLogs '*') -Destination $script:LogRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Alte Daten bleiben unangetastet; ein Migrationsfehler darf den Start nicht blockieren.
    }
}

function Initialize-AppSettings {
    Initialize-DataMigration
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            $settings = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($script:LanguageCodes -contains [string]$settings.Language) {
                $script:Language = [string]$settings.Language
            }
        }
        catch { }
    }
    Import-HistoryFromExistingLogs
}

function Save-AppSettings {
    New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
    [PSCustomObject]@{ Language = $script:Language } |
        ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Get-LanguageDisplayName {
    param([Parameter(Mandatory = $true)][string]$Code)
    $names = @{ de = 'Deutsch'; en = 'English'; es = 'Español'; fr = 'Français'; ru = 'Русский'; tr = 'Türkçe' }
    return [string]$names[$Code]
}

function global:Write-LogEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info',
        [string]$Component = 'REMNEXA'
    )

    $global:ProgramCleanerLogLines.Add(('[{0:yyyy-MM-dd HH:mm:ss}] [{1}] [{2}] {3}' -f (Get-Date), $Level, $Component, $Message))
}

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Cyan' }
    }

    Write-Host $Message -ForegroundColor $color
    Write-LogEntry -Message $Message -Level $Level
}

function Initialize-AntivirusModule {
    if ($script:AntivirusAvailable) { return $true }
    try {
        if (-not (Test-Path -LiteralPath $script:AntivirusModulePath -PathType Leaf)) {
            throw "Modulmanifest nicht gefunden unter '$script:AntivirusModulePath'."
        }
        Import-Module -Name $script:AntivirusModulePath -Force -ErrorAction Stop
        $script:AntivirusAvailable = $true
        Write-LogEntry -Message 'Antivirus-Modul wurde geladen.' -Component 'Antivirus/Integration'
        return $true
    }
    catch {
        Write-Status (T 'AVNotAvailable' @($_.Exception.Message)) 'Warning'
        return $false
    }
}

function Get-AntivirusTracePaths {
    param(
        [AllowNull()][object]$Identity,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces
    )

    $paths = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Identity) {
        foreach ($installPath in @($Identity.InstallPaths)) {
            if ($installPath -and (Test-Path -LiteralPath $installPath)) { $paths.Add([string]$installPath) }
        }
    }
    foreach ($trace in @($Traces | Where-Object { $_.Kind -in @('File', 'Directory') })) {
        if ($trace.Target -and (Test-Path -LiteralPath ([string]$trace.Target))) { $paths.Add([string]$trace.Target) }
    }
    return @($paths | Sort-Object -Unique)
}

function Invoke-ConfiguredAntivirusScan {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Before', 'After')][string]$Stage,
        [AllowNull()][object]$Identity,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces
    )

    if (-not (Initialize-AntivirusModule)) { return @() }
    try {
        $config = Get-AVConfig
        $enabled = if ($Stage -eq 'Before') { [bool]$config.ScanBeforeRemoval } else { [bool]$config.ScanAfterRemoval }
        if (-not $enabled) { return @() }
        $targets = @(Get-AntivirusTracePaths -Identity $Identity -Traces $Traces)
        if ($targets.Count -eq 0) {
            Write-LogEntry -Message "ClamAV-$Stage-Scan uebersprungen: keine Datei- oder Ordnerziele." -Component 'Antivirus/Integration'
            return @()
        }

        $status = Get-ClamAVStatus
        if (-not $status.Installed) {
            throw "ClamAV nicht gefunden unter '$($status.ClamScanPath)'. Bitte im Hauptmenue [9], dann [6] einrichten."
        }
        if ([bool]$config.AutoUpdateSignatures -and $status.SignaturesOutdated) {
            try { [void](Update-ClamAVSignature) }
            catch { Write-Status (T 'AVOptionalFailed' @($_.Exception.Message)) 'Warning' }
        }
        $scanResults = @(Invoke-ClamAVTargetedScan -Path $targets)
        $findings = @($scanResults | Where-Object { $_.Severity -in @('Malware', 'PotentiallyUnwanted') })
        if ($findings.Count -gt 0) {
            Write-Status (T 'AVFindings' @($findings.Count)) 'Warning'
        }
        else {
            Write-Status (T 'AVClean') 'Success'
        }
        return $scanResults
    }
    catch {
        Write-Status (T 'AVOptionalFailed' @($_.Exception.Message)) 'Warning'
        Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Antivirus/Integration'
        return @()
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-SingleQuotedLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Set-OperationProgress {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(1, 100)][int]$Percent,
        [Parameter(Mandatory = $true)][string]$Status
    )

    Write-Progress -Activity $script:BrandName -Status (('{0}% - {1}' -f $Percent, $Status)) -PercentComplete $Percent
    Write-Host ('[{0,3}%] {1}' -f $Percent, $Status) -ForegroundColor DarkCyan
}

function Complete-OperationProgress {
    Write-Progress -Activity $script:BrandName -Completed
}

function Request-ElevationForRemoval {
    param(
        [Parameter(Mandatory = $true)][string]$SearchName,
        [AllowNull()][object]$Program,
        [bool]$IsResidualOnly,
        [bool]$ContinueSession,
        [bool]$ProtectedOverride,
        [bool]$ProvisionedAppx
    )

    if (Test-IsAdministrator) { return $true }
    if ($NoElevation) {
        Write-Status (T 'AdminRequired') 'Warning'
        return $false
    }

    Write-Status (T 'UacOpening') 'Warning'

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('& ' + (ConvertTo-SingleQuotedLiteral -Value $PSCommandPath))
    $parts.Add('-Name ' + (ConvertTo-SingleQuotedLiteral -Value $SearchName))
    $parts.Add('-ResumeRemoval')
    $parts.Add('-WorkspaceMode Uninstall')
    if ($IncludeUserFiles) { $parts.Add('-IncludeUserFiles') }
    if ($IsResidualOnly) { $parts.Add('-ResidualOnly') }
    if ($NoRestorePoint) { $parts.Add('-NoRestorePoint') }
    if ($ProtectedOverride) { $parts.Add('-OverrideProtectedComponent') }
    if ($ProvisionedAppx) { $parts.Add('-RemoveProvisionedAppx') }
    if ($TestIntegrity) { $parts.Add('-TestIntegrity') }
    if ($ContinueSession) { $parts.Add('-ContinueInteractive') }
    if ($null -ne $Program -and $Program.RegistryPath) {
        $parts.Add('-SelectedRegistryPath ' + (ConvertTo-SingleQuotedLiteral -Value ([string]$Program.RegistryPath)))
    }
    if ($null -ne $Program -and $Program.PackageFullName) {
        $parts.Add('-SelectedPackageFullName ' + (ConvertTo-SingleQuotedLiteral -Value ([string]$Program.PackageFullName)))
    }

    $command = $parts -join ' '
    $bytes = [Text.Encoding]::Unicode.GetBytes($command)
    $encoded = [Convert]::ToBase64String($bytes)

    try {
        $currentPowerShell = (Get-Process -Id $PID).Path
        Start-Process -FilePath $currentPowerShell -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
        ) -WorkingDirectory $PSScriptRoot | Out-Null
        exit 0
    }
    catch {
        Write-Status (T 'UacCancelled') 'Warning'
        return $false
    }
}

function Request-ElevationForTool {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Registry', 'Features', 'Privacy', 'Antivirus', 'Startup')][string]$Mode,
        [AllowEmptyString()][string]$ItemId = ''
    )

    if (Test-IsAdministrator) { return $true }
    if ($NoElevation) {
        Write-Status (T 'AdminRequired') 'Warning'
        return $false
    }

    Write-Status (T 'UacOpening') 'Warning'
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('& ' + (ConvertTo-SingleQuotedLiteral -Value $PSCommandPath))
    $parts.Add('-ToolMode ' + (ConvertTo-SingleQuotedLiteral -Value $Mode))
    $parts.Add('-ContinueInteractive')
    if ($Mode -eq 'Startup') { $parts.Add('-WorkspaceMode Startup') }
    if ($Mode -eq 'Startup' -and -not [string]::IsNullOrWhiteSpace($ItemId)) {
        $parts.Add('-SelectedStartupId ' + (ConvertTo-SingleQuotedLiteral -Value $ItemId))
    }
    if ($NoRestorePoint) { $parts.Add('-NoRestorePoint') }
    if ($OverrideProtectedComponent) { $parts.Add('-OverrideProtectedComponent') }
    $command = $parts -join ' '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    try {
        $currentPowerShell = (Get-Process -Id $PID).Path
        Start-Process -FilePath $currentPowerShell -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
        ) -WorkingDirectory $PSScriptRoot | Out-Null
        exit 0
    }
    catch {
        Write-Status (T 'UacCancelled') 'Warning'
        return $false
    }
}

function Normalize-Text {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text.ToLowerInvariant()) -replace '[^\p{L}\p{Nd}]', '')
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($null -eq $InputObject) { return '' }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return $property.Value
}

function Get-ProtectedComponentMatch {
    param(
        [AllowNull()][object]$Program,
        [AllowEmptyString()][string]$SearchName = ''
    )

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($SearchName)) { $parts.Add($SearchName) }
    if ($null -ne $Program) {
        foreach ($propertyName in @('DisplayName', 'PackageName', 'PackageFullName', 'Publisher', 'ProductCode')) {
            $value = [string](Get-OptionalPropertyValue -InputObject $Program -PropertyName $propertyName)
            if (-not [string]::IsNullOrWhiteSpace($value)) { $parts.Add($value) }
        }
    }
    $combined = $parts -join ' | '
    foreach ($rule in $script:ProtectedComponents) {
        if ($combined -match $rule.Pattern) { return $rule }
    }
    return $null
}

function Confirm-ProtectedComponentOverride {
    param(
        [AllowNull()][object]$Program,
        [Parameter(Mandatory = $true)][string]$SearchName
    )

    $match = Get-ProtectedComponentMatch -Program $Program -SearchName $SearchName
    if ($null -eq $match) { return $true }

    Write-Host ''
    Write-Host (T 'ProtectedTitle') -ForegroundColor Red
    Write-Host (T 'ProtectedReason' @([string]$match.Category)) -ForegroundColor Red
    if ($OverrideProtectedComponent) {
        $script:ProtectedOverrideCategory = [string]$match.Category
        Write-Status (T 'ProtectedOverride') 'Warning'
        return $true
    }
    if (-not $script:InteractiveSession) { return $false }

    Write-Host ('  [1] ' + (T 'ProtectedAbort'))
    Write-Host ('  [2] ' + (T 'ProtectedOverride')) -ForegroundColor Red
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return $false }
        if ($answer -eq '2') {
            $script:OverrideProtectedComponent = $true
            $script:ProtectedOverrideCategory = [string]$match.Category
            return $true
        }
        Write-Status (T 'InvalidProtected') 'Warning'
    }
}

function Test-ProtectedServiceName {
    param([Parameter(Mandatory = $true)][string]$ServiceName)
    if ($script:ProtectedServices -notcontains $ServiceName) { return $false }
    $category = if ($ServiceName -in @('WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wscsvc')) {
        'Windows Defender / Security Center'
    }
    elseif ($ServiceName -in @('wuauserv', 'WaaSMedicSvc', 'UsoSvc', 'BITS', 'DoSvc')) {
        'Windows Update'
    }
    else {
        'Microsoft Store infrastructure'
    }
    return $script:ProtectedOverrideCategory -ne $category
}

function Get-SystemDriveFreeBytes {
    try {
        $root = [IO.Path]::GetPathRoot($env:WINDIR)
        return [int64]([IO.DriveInfo]::new($root).AvailableFreeSpace)
    }
    catch { return [int64]-1 }
}

function Format-ByteSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} Bytes' -f $Bytes)
}

function Get-InstalledPrograms {
    $items = New-Object System.Collections.Generic.List[object]
    $registryRoots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($entry in @(Get-ItemProperty -Path $registryRoots -ErrorAction SilentlyContinue)) {
        $entryDisplayName = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayName')
        if ([string]::IsNullOrWhiteSpace($entryDisplayName)) { continue }

        $uninstallString = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'UninstallString')
        $quietUninstallString = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'QuietUninstallString')
        $systemComponent = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'SystemComponent')
        $releaseType = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'ReleaseType')
        $parentKeyName = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'ParentKeyName')
        $publisher = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'Publisher')
        $protectionMatch = Get-ProtectedComponentMatch -Program ([PSCustomObject]@{ DisplayName = $entryDisplayName; Publisher = $publisher }) -SearchName $entryDisplayName
        $looksSystemLike = (
            $systemComponent -eq '1' -or
            -not [string]::IsNullOrWhiteSpace($parentKeyName) -or
            $releaseType -match 'Update|Hotfix|Security|Rollup' -or
            $entryDisplayName -match '^(Update für|Update for|Security Update|Sicherheitsupdate|Hotfix|KB\d+)' -or
            $entryDisplayName -match '^Microsoft Visual C\+\+' -or
            $entryDisplayName -match '^Microsoft \.NET' -or
            $entryDisplayName -match 'Windows Desktop Runtime|WebView2.*(Runtime|Laufzeit)|Software Development Kit|\bSDK\b' -or
            ($publisher -match '^Microsoft' -and $entryDisplayName -match 'Runtime|Laufzeit|Framework|Redistributable|Health Tools') -or
            $entryDisplayName -match '\b(Driver|Treiberpaket)\b'
        )

        $items.Add([PSCustomObject]@{
            Type                 = 'Registry'
            SourceLabel          = 'Desktop'
            DisplayName          = $entryDisplayName
            DisplayVersion       = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayVersion')
            Publisher            = $publisher
            InstallLocation      = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'InstallLocation')
            InstallSource        = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'InstallSource')
            UninstallString      = $uninstallString
            QuietUninstallString = $quietUninstallString
            RegistryPath         = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSPath')
            ProductCode          = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSChildName')
            PackageFullName      = ''
            PackageName          = ''
            IsSystemLike         = [bool]($looksSystemLike -or $null -ne $protectionMatch)
            ProtectionCategory   = $(if ($null -ne $protectionMatch) { [string]$protectionMatch.Category } else { '' })
            CanUninstall         = -not ([string]::IsNullOrWhiteSpace($uninstallString) -and [string]::IsNullOrWhiteSpace($quietUninstallString))
        })
    }

    try {
        foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
            $display = if ($package.Name) { [string]$package.Name } else { [string]$package.PackageFullName }
            $isFramework = [bool](Get-OptionalPropertyValue -InputObject $package -PropertyName 'IsFramework')
            $isResourcePackage = [bool](Get-OptionalPropertyValue -InputObject $package -PropertyName 'IsResourcePackage')
            $nonRemovable = [bool](Get-OptionalPropertyValue -InputObject $package -PropertyName 'NonRemovable')
            $protectionMatch = Get-ProtectedComponentMatch -Program $package -SearchName $display
            $items.Add([PSCustomObject]@{
                Type                 = 'Appx'
                SourceLabel          = 'Store'
                DisplayName          = $display
                DisplayVersion       = [string]$package.Version
                Publisher            = [string]$package.Publisher
                InstallLocation      = [string]$package.InstallLocation
                InstallSource        = ''
                UninstallString      = ''
                QuietUninstallString = ''
                RegistryPath         = ''
                ProductCode          = ''
                PackageFullName      = [string]$package.PackageFullName
                PackageName          = [string]$package.Name
                IsSystemLike         = [bool]($isFramework -or $isResourcePackage -or $nonRemovable -or $null -ne $protectionMatch)
                ProtectionCategory   = $(if ($null -ne $protectionMatch) { [string]$protectionMatch.Category } else { '' })
                CanUninstall         = -not $nonRemovable
            })
        }
    }
    catch {
        Write-Status (T 'StoreReadError' @($_.Exception.Message)) 'Warning'
    }

    return @($items | Sort-Object DisplayName, DisplayVersion, Type, RegistryPath -Unique)
}

function Find-ProgramCandidates {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Programs,
        [Parameter(Mandatory = $true)][string]$SearchName
    )

    $needle = $SearchName.Trim()
    return @($Programs | Where-Object {
        $_.DisplayName.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $_.Publisher.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } | Sort-Object @{
        Expression = { if ($_.DisplayName.Equals($needle, [StringComparison]::OrdinalIgnoreCase)) { 0 } else { 1 } }
    }, DisplayName, DisplayVersion)
}

function Select-Program {
    param([Parameter(Mandatory = $true)][object[]]$Candidates)

    return Select-ProgramPaged -Programs $Candidates -Title (T 'FoundProgramsTitle')
}

function Select-ProgramPaged {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Programs,
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowNull()][object]$ResumeContext = $null
    )

    if ($Programs.Count -eq 0) {
        Write-Status (T 'NoApps') 'Warning'
        return $null
    }

    $allPrograms = @($Programs | Sort-Object DisplayName, DisplayVersion, SourceLabel)
    $filteredPrograms = $allPrograms
    $filterText = ''
    $page = 0
    if ($null -ne $ResumeContext) { $filterText = [string]$ResumeContext.Filter; $page = [int]$ResumeContext.Page }
    $filteredPrograms = if ($filterText) { @($allPrograms | Where-Object { $_.DisplayName.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Publisher.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) } else { $allPrograms }
    $pageSize = 18

    while ($true) {
        Clear-Host
        Show-BrandHeader
        Write-Host $Title -ForegroundColor White
        if ($filterText) { Write-Host (T 'FilterLabel' @($filterText)) -ForegroundColor Yellow }

        $pageCount = [Math]::Max(1, [Math]::Ceiling($filteredPrograms.Count / [double]$pageSize))
        if ($page -ge $pageCount) { $page = $pageCount - 1 }
        if ($page -lt 0) { $page = 0 }
        $script:LastProgramListContext = [PSCustomObject]@{ Programs = $allPrograms; Title = $Title; Filter = $filterText; Page = $page }
        $start = $page * $pageSize
        $end = [Math]::Min($start + $pageSize - 1, $filteredPrograms.Count - 1)

        Write-Host (T 'PageLabel' @(($page + 1), $pageCount, $filteredPrograms.Count)) -ForegroundColor DarkGray
        Write-Host ''
        if ($filteredPrograms.Count -eq 0) {
            Write-Host (T 'NoFilterHits') -ForegroundColor Yellow
        }
        else {
            for ($i = $start; $i -le $end; $i++) {
                $item = $filteredPrograms[$i]
                $version = if ($item.DisplayVersion) { ' | ' + $item.DisplayVersion } else { '' }
                $protectionCategory = [string](Get-OptionalPropertyValue -InputObject $item -PropertyName 'ProtectionCategory')
                $protected = if (-not $item.CanUninstall -or -not [string]::IsNullOrWhiteSpace($protectionCategory)) { ' | ' + (T 'ProtectedLabel') } else { '' }
                Write-Host ('  [{0}] {1}{2} | {3}{4}' -f ($i + 1), $item.DisplayName, $version, $item.SourceLabel, $protected)
            }
        }

        Write-Host ''
        Write-Host (T 'ListCommands') -ForegroundColor DarkGray
        $answer = Read-Host (T 'SelectPrompt')
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Status (T 'InvalidList') 'Warning'
            Start-Sleep -Milliseconds 900
            continue
        }

        $trimmedAnswer = $answer.Trim()
        if ($trimmedAnswer -in @('0', 'exit')) {
            $script:ExitRequested = $true
            return $null
        }
        if ($trimmedAnswer -in @('-5', 'b', 'back', 'menu')) { return $null }
        if ($trimmedAnswer -in @('-1', 'n')) {
            if ($page + 1 -lt $pageCount) { $page++ }
            continue
        }
        if ($trimmedAnswer -in @('-2', 'z')) {
            if ($page -gt 0) { $page-- }
            continue
        }
        if ($trimmedAnswer -in @('-3', 's')) {
            $filterText = (Read-Host (T 'SearchPrompt')).Trim()
            if ($filterText) {
                $filteredPrograms = @($allPrograms | Where-Object {
                    $_.DisplayName.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    $_.Publisher.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0
                })
            }
            else {
                $filteredPrograms = $allPrograms
            }
            $page = 0
            continue
        }
        if ($trimmedAnswer -in @('-4', 'a')) {
            $filterText = ''
            $filteredPrograms = $allPrograms
            $page = 0
            continue
        }

        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $filteredPrograms.Count) {
            $selectedProgram = $filteredPrograms[$number - 1]
            if (-not $selectedProgram.CanUninstall) {
                Write-Status (T 'ProtectedItem') 'Warning'
                Write-Host (T 'Press1Back') -ForegroundColor DarkGray
                while ($true) {
                    $protectedChoice = (Read-Host (T 'SelectPrompt')).Trim()
                    if ($protectedChoice -eq '1') { break }
                    if ($protectedChoice -in @('0', 'exit')) {
                        $script:ExitRequested = $true
                        return $null
                    }
                    Write-Status (T 'Press1Back') 'Warning'
                }
                continue
            }
            $script:LastProgramListContext.Filter = $filterText
            $script:LastProgramListContext.Page = $page
            return $selectedProgram
        }

        Write-Status (T 'InvalidList') 'Warning'
        Start-Sleep -Milliseconds 900
    }
}

function Show-UninstallMenu {
    Write-Host (T 'UninstallTitle') -ForegroundColor White
    Write-Host ''
    Write-Host (T 'MainQuestion') -ForegroundColor White
    Write-Host ''
    Write-Host ('  [1] ' + (T 'Main1'))
    Write-Host ('  [2] ' + (T 'Main2'))
    Write-Host ('  [3] ' + (T 'Main3'))
    Write-Host ('  [4] ' + (T 'Main4'))
    Write-Host ('  [5] ' + (T 'Main5'))
    Write-Host ('  [6] ' + (T 'Main6'))
    Write-Host ('  [7] ' + (T 'Main7'))
    Write-Host ('  [8] ' + (T 'Main8'))
    Write-Host ('  [9] ' + (T 'Main9'))
    Write-Host ('  [0] ' + (T 'BackHome'))
    Write-Host ''

    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -match '^[0-9]$') { return $answer }
        if ($answer -ieq 'exit') { return '0' }
        Write-Status (T 'InvalidMain') 'Warning'
    }
}

function Show-HomeMenu {
    Write-Host (T 'HomeTitle') -ForegroundColor White
    Write-Host (T 'HomeDescription') -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('  [1] ' + (T 'Home1'))
    Write-Host ('  [2] ' + (T 'Home2'))
    Write-Host ('  [3] ' + (T 'Home3'))
    Write-Host ('  [4] ' + (T 'Home4'))
    Write-Host ('  [5] ' + (T 'Home5'))
    Write-Host ('  [6] ' + (T 'Home6'))
    Write-Host ('  [7] ' + (T 'Home7'))
    Write-Host ('  [8] ' + (T 'Home8'))
    Write-Host ('  [0] ' + (T 'Main0'))
    Write-Host ''
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -match '^[0-8]$') { return $answer }
        if ($answer -ieq 'exit') { return '0' }
        Write-Status (T 'HomeInvalid') 'Warning'
    }
}

function Read-AfterOperationChoice {
    Write-Host ''
    Write-Host (T 'OperationDone') -ForegroundColor White
    Write-Host ('  [1] ' + (T 'BackMain'))
    Write-Host ('  [2] ' + (T 'BackProgramList'))
    if ($script:LastRunLogPath) { Write-Host ('  [3] ' + (T 'OpenRunLog')) }
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $choice = (Read-Host (T 'SelectPrompt')).Trim()
        if ($choice -eq '3' -and $script:LastRunLogPath) {
            if (Test-Path -LiteralPath $script:LastRunLogPath) {
                Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:LastRunLogPath + '"') -Wait
            }
            else { Write-Status ('Protokoll nicht gefunden: ' + $script:LastRunLogPath) 'Warning' }
            Show-LastRunDetails
            Write-Host (T 'OperationDone') -ForegroundColor White
            Write-Host ('  [1] ' + (T 'BackMain'))
            Write-Host ('  [2] ' + (T 'BackProgramList'))
            Write-Host ('  [3] ' + (T 'OpenRunLog'))
            Write-Host ('  [0] ' + (T 'Main0'))
            continue
        }
        if ($choice -eq '1') { return 'main' }
        if ($choice -eq '2') { return 'list' }
        if ($choice -eq '0') { return 'exit' }
        Write-Status (T $(if ($script:LastRunLogPath) { 'InvalidAfterOperation' } else { 'InvalidAfterOperationNoLog' })) 'Warning'
    }
}

function Show-LastRunDetails {
    if ($null -eq $script:LastRunSummary) { return }
    $summary = $script:LastRunSummary
    Write-Host ''
    Write-Host (T 'RunDetails') -ForegroundColor White
    Write-Host ('  Spuren vor der Deinstallation: {0}' -f $summary.Before)
    Write-Host ('  Spuren danach zur Bereinigung gefunden: {0}' -f $summary.Found)
    Write-Host ('  Entfernt: {0} | fehlgeschlagen: {1} | noch vorhanden: {2}' -f $summary.Removed, $summary.Failed, $summary.Remaining)
    if ($summary.Integrity) {
        if ($summary.Integrity.Warnings.Count -eq 0) { Write-Host '  Systemprüfung: keine Hinweise.' -ForegroundColor Green }
        else {
            Write-Host ('  Systemprüfung: {0} Hinweis(e)' -f $summary.Integrity.Warnings.Count) -ForegroundColor Yellow
            foreach ($warning in $summary.Integrity.Warnings) { Write-Host ('    - ' + $warning) -ForegroundColor Yellow }
            foreach ($check in @($summary.Integrity.Checks | Where-Object { -not $_.Healthy })) {
                Write-Host ('      {0}: {1}{2}' -f $check.Display, $check.State, $(if ($check.StartMode) { ' | Starttyp: ' + $check.StartMode } else { '' })) -ForegroundColor DarkYellow
            }
        }
    }
}

function Get-ExecutableFromCommandLine {
    param([AllowNull()][string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^\s*"([^"]+\.exe)"') { return $matches[1] }
    if ($expanded -match '^\s*(.+?\.exe)(?:\s|$)') { return $matches[1].Trim() }
    return ''
}

function Split-CommandLine {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^\s*"([^"]+\.exe)"\s*(.*)$') {
        return @($matches[1], $matches[2])
    }
    if ($expanded -match '^\s*(.+?\.exe)\s*(.*)$') {
        return @($matches[1].Trim(), $matches[2])
    }
    throw ('Unbekanntes Deinstallationskommando: ' + $CommandLine)
}

function Get-IdentityInfo {
    param(
        [Parameter(Mandatory = $true)][string]$SearchName,
        [AllowNull()][object]$Program
    )

    $blockedTokens = @(
        'app', 'application', 'desktop', 'program', 'software', 'windows', 'microsoft',
        'client', 'launcher', 'update', 'updater', 'setup', 'installer', 'install',
        'service', 'helper', 'tool', 'tools', 'suite', 'edition', 'version', 'official',
        'x64', 'x86', '64bit', '32bit', 'gmbh', 'llc', 'inc', 'ltd', 'corp', 'corporation'
    )

    $rawNames = New-Object System.Collections.Generic.List[string]
    $paths = New-Object System.Collections.Generic.List[string]
    $rawNames.Add($SearchName.Trim())
    $deepRegistrySource = $SearchName.Trim()

    if ($null -ne $Program) {
        if ($Program.DisplayName) {
            $rawNames.Add([string]$Program.DisplayName)
            $deepRegistrySource = [string]$Program.DisplayName
        }
        if ($Program.PackageName) { $rawNames.Add([string]$Program.PackageName) }

        $identityPaths = New-Object System.Collections.Generic.List[string]
        if ($Program.Type -ne 'Appx' -and $Program.InstallLocation) {
            $identityPaths.Add([string]$Program.InstallLocation)
        }

        foreach ($uninstallCommand in @($Program.UninstallString, $Program.QuietUninstallString)) {
            $uninstallExecutable = Get-ExecutableFromCommandLine $uninstallCommand
            if (-not [string]::IsNullOrWhiteSpace($uninstallExecutable) -and [IO.Path]::IsPathRooted($uninstallExecutable)) {
                $uninstallDirectory = [IO.Path]::GetDirectoryName($uninstallExecutable)
                $insideWindows = $uninstallDirectory.StartsWith($env:WINDIR.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
                $insidePackageCache = $uninstallDirectory.StartsWith((Join-Path $env:ProgramData 'Package Cache').TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
                if (-not $insideWindows -and -not $insidePackageCache) {
                    $identityPaths.Add($uninstallDirectory)
                }
                $rawNames.Add([IO.Path]::GetFileNameWithoutExtension($uninstallExecutable))
            }
        }

        foreach ($path in @($identityPaths)) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            try {
                $fullPath = [IO.Path]::GetFullPath($path)
                if ([IO.Path]::GetExtension($fullPath)) {
                    $rawNames.Add([IO.Path]::GetFileNameWithoutExtension($fullPath))
                    $directory = [IO.Path]::GetDirectoryName($fullPath)
                    if ($directory) { $paths.Add($directory) }
                }
                else {
                    $paths.Add($fullPath)
                    $rawNames.Add((Split-Path -Leaf $fullPath))
                }
            }
            catch { }
        }
    }

    $aliases = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($rawNames)) {
        $normalizedFull = Normalize-Text $raw
        if ($normalizedFull.Length -ge 4 -and $blockedTokens -notcontains $normalizedFull) {
            $aliases.Add($normalizedFull)
        }

        foreach ($token in @($raw -split '[^\p{L}\p{Nd}]+')) {
            $normalizedToken = Normalize-Text $token
            if ($normalizedToken.Length -ge 4 -and $blockedTokens -notcontains $normalizedToken) {
                $aliases.Add($normalizedToken)
            }
        }
    }

    $uniqueAliases = @($aliases | Sort-Object Length -Descending -Unique)
    if ($uniqueAliases.Count -eq 0) {
        throw 'Aus diesem Programmnamen lässt sich kein sicherer Suchbegriff bilden. Bitte einen genaueren Namen eingeben.'
    }

    # Für die langsame Registry-Volltextsuche wird nur ein ausreichend
    # eindeutiger Begriff verwendet. Kurze gewöhnliche Wörter wie "Java" oder
    # "Edge" wären dafür zu breit; kurze echte Akronyme wie "IBKR" sind erlaubt.
    $deepRegistryTerm = ''
    $sourceTokens = @($deepRegistrySource -split '[^\p{L}\p{Nd}]+')
    [array]::Reverse($sourceTokens)
    foreach ($token in $sourceTokens) {
        $normalizedToken = Normalize-Text $token
        if ($blockedTokens -contains $normalizedToken) { continue }
        $isAcronym = $token -cmatch '^[A-Z0-9]{3,5}$' -and $token -cmatch '[A-Z]'
        if ($normalizedToken.Length -ge 5 -or $isAcronym) {
            $deepRegistryTerm = $token
            break
        }
    }

    return [PSCustomObject]@{
        Aliases          = $uniqueAliases
        InstallPaths     = @($paths | Sort-Object -Unique)
        DeepRegistryTerm = $deepRegistryTerm
    }
}

function Test-NameMatch {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory = $true)][string[]]$Aliases
    )

    $normalized = Normalize-Text $Value
    if (-not $normalized) { return $false }
    foreach ($alias in $Aliases) {
        if ($normalized.Equals($alias, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($alias.Length -ge 6 -and $normalized.Contains($alias)) { return $true }

        # Bei kurzen Begriffen sind nur echte Wort-/Pfadgrenzen erlaubt. So
        # trifft "Java" auf java.exe, aber nicht auf einen gemeinsamen JavaSoft-
        # Schlüssel oder auf JavaScript-Dateien.
        if ($alias.Length -ge 4) {
            $boundaryPattern = '(?i)(?<![\p{L}\p{Nd}])' + [regex]::Escape($alias) + '(?![\p{L}\p{Nd}])'
            if ($Value -match $boundaryPattern) { return $true }
        }
    }
    return $false
}

function Add-Trace {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('File', 'Directory', 'RegistryKey', 'RegistryValue', 'Service', 'Task')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$ValueName = '',
        [string]$Reason = '',
        [bool]$Personal = $false
    )

    if ([string]::IsNullOrWhiteSpace($Target)) { return }
    if ($Kind -eq 'Service' -and (Test-ProtectedServiceName -ServiceName $Target)) {
        Write-Status (T 'ProtectedReason' @($Target)) 'Warning'
        return
    }
    $key = ($Kind + '|' + $Target + '|' + $ValueName).ToLowerInvariant()
    if ($script:TraceIndex.ContainsKey($key)) { return }

    $trace = [PSCustomObject]@{
        Kind      = $Kind
        Target    = $Target
        ValueName = $ValueName
        Reason    = $Reason
        Personal  = $Personal
    }
    $script:TraceIndex[$key] = $trace
}

function Test-ProtectedFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $true }
    $protected = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(
        [IO.Path]::GetPathRoot($full),
        $env:USERPROFILE,
        $env:APPDATA,
        $env:LOCALAPPDATA,
        $env:ProgramData,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:WINDIR,
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Downloads')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            try { $protected.Add([IO.Path]::GetFullPath($item).TrimEnd('\')) } catch { }
        }
    }

    if (@($protected | Where-Object { $_.Equals($full, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        return $true
    }

    # Unter Windows dürfen einzelne Cache-Dateien entfernt werden, niemals aber
    # ein kompletter Systemordner oder dessen Unterordner.
    try {
        $existingItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        $windowsRoot = [IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')
        if ($existingItem -and $existingItem.PSIsContainer -and
            $full.StartsWith($windowsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    catch { }

    return $false
}

function Add-FileTraceIfSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Reason,
        [bool]$Personal = $false
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-ProtectedFilePath -Path $Path) {
        Write-Status (T 'SafetyParent' @($Path)) 'Warning'
        return
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Status (T 'SafetyLink' @($Path)) 'Warning'
            return
        }
        Add-Trace -Kind $(if ($item.PSIsContainer) { 'Directory' } else { 'File' }) -Target $item.FullName -Reason $Reason -Personal $Personal
    }
    catch {
        Write-Status (T 'PathCheckError' @($Path)) 'Warning'
    }
}

function Find-MatchingChildren {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [int]$MaxDepth = 2,
        [bool]$Personal = $false
    )

    if (-not (Test-Path -LiteralPath $Root)) { return }
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([PSCustomObject]@{ Path = $Root; Depth = 0 })

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($child in @(Get-ChildItem -LiteralPath $current.Path -Force -ErrorAction SilentlyContinue)) {
            $isOwnData = $false
            foreach ($ownDataRoot in @($script:DataRoot, $script:LegacyDataRoot)) {
                if ($child.FullName.StartsWith($ownDataRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
                    $child.FullName.Equals($ownDataRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    $isOwnData = $true
                    break
                }
            }
            if ($isOwnData) {
                continue
            }
            if (Test-NameMatch -Value $child.Name -Aliases $Aliases) {
                Add-FileTraceIfSafe -Path $child.FullName -Reason 'Name passt zum ausgewählten Programm' -Personal $Personal
                continue
            }
            if ($child.PSIsContainer -and $current.Depth -lt $MaxDepth -and (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) {
                $queue.Enqueue([PSCustomObject]@{ Path = $child.FullName; Depth = $current.Depth + 1 })
            }
        }
    }
}

function Test-ProtectedRegistryKey {
    param([Parameter(Mandatory = $true)][string]$RegistryPath)

    $upper = $RegistryPath.ToUpperInvariant()
    if ($upper -match '^HKEY_LOCAL_MACHINE\\(SYSTEM|HARDWARE|SAM|SECURITY)(\\|$)') { return $true }
    if ($upper -match '\\SOFTWARE\\MICROSOFT\\WINDOWS\\CURRENTVERSION\\INSTALLER(\\|$)') { return $true }
    if ($upper -match '\\SOFTWARE\\CLASSES\\(CLSID|INTERFACE|TYPELIB)(\\|$)') { return $true }
    $protectedCategory = ''
    if ($upper -match '\\(MICROSOFT\\)?(WINDOWS DEFENDER|SECURITY CENTER)(\\|$)') {
        $protectedCategory = 'Windows Defender / Security Center'
    }
    elseif ($upper -match '\\(MICROSOFT\\)?(WINDOWSUPDATE|WINDOWS UPDATE)(\\|$)') {
        $protectedCategory = 'Windows Update'
    }
    elseif ($upper -match '\\MICROSOFT\\WINDOWS\\CURRENTVERSION\\(WINDOWSUPDATE)(\\|$)') {
        $protectedCategory = 'Windows Update'
    }
    elseif ($upper -match '\\(WINDOWSSTORE|APPX)(\\|$)' -or $upper -match '\\MICROSOFT\\WINDOWS\\CURRENTVERSION\\(APPX|APPMODEL|STORE)(\\|$)') {
        $protectedCategory = 'Microsoft Store infrastructure'
    }
    elseif ($upper -match '\\(DOTNET|NET FRAMEWORK|\.NETFRAMEWORK)(\\|$)') {
        $protectedCategory = '.NET Framework / Runtime'
    }
    elseif ($upper -match '\\MICROSOFT\\VISUALSTUDIO\\[^\\]+\\VC\\RUNTIMES(\\|$)') {
        $protectedCategory = 'Microsoft Visual C++ Redistributable'
    }
    if ($protectedCategory -and $script:ProtectedOverrideCategory -ne $protectedCategory) { return $true }
    return $false
}

function Find-RegistryTraces {
    param(
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [AllowEmptyString()][string]$DeepRegistryTerm,
        [AllowNull()][object]$Program
    )

    if ($null -ne $Program -and $Program.RegistryPath) {
        $nativePath = $Program.RegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
        Add-Trace -Kind 'RegistryKey' -Target $nativePath -Reason 'Deinstallationseintrag des ausgewählten Programms'
    }

    # Maschinenweite Programmschlüssel werden bis zu zwei Ebenen tief anhand
    # ihres Namens geprüft. Das vermeidet eine sehr langsame Volltextsuche durch
    # sämtliche Windows- und Installer-Datenbanken.
    foreach ($root in @(
        'Registry::HKEY_LOCAL_MACHINE\Software',
        'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node',
        'Registry::HKEY_CURRENT_USER\Software'
    )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([PSCustomObject]@{ Path = $root; Depth = 0 })
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            foreach ($child in @(Get-ChildItem -LiteralPath $current.Path -ErrorAction SilentlyContinue)) {
                $nativePath = $child.Name
                if ((Test-NameMatch -Value $child.PSChildName -Aliases $Aliases) -and -not (Test-ProtectedRegistryKey -RegistryPath $nativePath)) {
                    Add-Trace -Kind 'RegistryKey' -Target $nativePath -Reason 'Programmspezifischer Registrierungsschlüssel'
                    continue
                }
                if ($current.Depth -lt 1 -and -not (Test-ProtectedRegistryKey -RegistryPath $nativePath)) {
                    $queue.Enqueue([PSCustomObject]@{ Path = $child.PSPath; Depth = $current.Depth + 1 })
                }
            }
        }
    }

    # Eine einzige Volltextsuche im Benutzerbereich erfasst auch Verlaufseinträge
    # wie MuiCache, AppCompat, Start-Kacheln und CloudStore.
    if ([string]::IsNullOrWhiteSpace($DeepRegistryTerm)) { return }

    $term = $DeepRegistryTerm
    $output = @(& reg.exe query 'HKCU\Software' /f $term /s 2>$null)
    $currentKey = ''
    foreach ($line in $output) {
        if ($line -match '^HKEY_') {
            $currentKey = $line.Trim()
            $leaf = ($currentKey -split '\\')[-1]
            if ((Test-NameMatch -Value $leaf -Aliases $Aliases) -and -not (Test-ProtectedRegistryKey -RegistryPath $currentKey)) {
                Add-Trace -Kind 'RegistryKey' -Target $currentKey -Reason ('Registrierungsschlüssel enthält ' + $term)
            }
            continue
        }

        if (-not $currentKey -or (Test-ProtectedRegistryKey -RegistryPath $currentKey)) { continue }
        if ($line -match '^\s{4}(.+?)\s{2,}(REG_[A-Z0-9_]+)\s{2,}(.*)$') {
            $valueName = $matches[1].Trim()
            $data = $matches[3]
            if ((Test-NameMatch -Value $valueName -Aliases $Aliases) -or (Test-NameMatch -Value $data -Aliases $Aliases)) {
                Add-Trace -Kind 'RegistryValue' -Target $currentKey -ValueName $valueName -Reason ('Registrierungswert enthält ' + $term)
            }
        }
    }
}

function Find-ServiceAndTaskTraces {
    param(
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$InstallPaths
    )

    try {
        foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
            $combined = ([string]$service.Name) + ' ' + ([string]$service.DisplayName) + ' ' + ([string]$service.PathName)
            $pathMatch = $false
            foreach ($path in $InstallPaths) {
                if ($path -and $combined.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $pathMatch = $true; break }
            }
            if ($pathMatch -or (Test-NameMatch -Value $combined -Aliases $Aliases)) {
                Add-Trace -Kind 'Service' -Target ([string]$service.Name) -Reason ([string]$service.DisplayName)
            }
        }
    }
    catch {
        Write-Status (T 'ServicesReadError' @($_.Exception.Message)) 'Warning'
    }

    try {
        foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            $actionTextParts = New-Object System.Collections.Generic.List[string]
            foreach ($action in @((Get-OptionalPropertyValue -InputObject $task -PropertyName 'Actions'))) {
                $execute = [string](Get-OptionalPropertyValue -InputObject $action -PropertyName 'Execute')
                $arguments = [string](Get-OptionalPropertyValue -InputObject $action -PropertyName 'Arguments')
                if ($execute -or $arguments) { $actionTextParts.Add($execute + ' ' + $arguments) }
            }
            $actionText = $actionTextParts -join ' '
            $combined = ([string]$task.TaskName) + ' ' + ([string]$task.TaskPath) + ' ' + $actionText
            $pathMatch = $false
            foreach ($path in $InstallPaths) {
                if ($path -and $combined.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $pathMatch = $true; break }
            }
            if ($pathMatch -or (Test-NameMatch -Value $combined -Aliases $Aliases)) {
                Add-Trace -Kind 'Task' -Target (([string]$task.TaskPath) + ([string]$task.TaskName)) -Reason 'Geplante Aufgabe'
            }
        }
    }
    catch {
        Write-Status (T 'TasksReadError' @($_.Exception.Message)) 'Warning'
    }
}

function Find-AllTraces {
    param(
        [Parameter(Mandatory = $true)][object]$Identity,
        [AllowNull()][object]$Program,
        [bool]$WithUserFiles = $false
    )

    $script:TraceIndex = @{}
    foreach ($path in $Identity.InstallPaths) {
        Add-FileTraceIfSafe -Path $path -Reason 'Installationspfad des ausgewählten Programms'
    }

    $systemRoots = @(
        @{ Path = $env:ProgramFiles; Depth = 2 },
        @{ Path = ${env:ProgramFiles(x86)}; Depth = 2 },
        @{ Path = $env:ProgramData; Depth = 2 },
        @{ Path = $env:LOCALAPPDATA; Depth = 2 },
        @{ Path = $env:APPDATA; Depth = 2 },
        @{ Path = $env:TEMP; Depth = 1 },
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'); Depth = 4 },
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'); Depth = 4 }
    )

    foreach ($root in $systemRoots) {
        if ($root.Path) {
            Find-MatchingChildren -Root $root.Path -Aliases $Identity.Aliases -MaxDepth $root.Depth
        }
    }

    try {
        $systemDriveRoot = [IO.Path]::GetPathRoot($env:WINDIR)
        Find-MatchingChildren -Root $systemDriveRoot -Aliases $Identity.Aliases -MaxDepth 0
    }
    catch { }

    $prefetch = Join-Path $env:WINDIR 'Prefetch'
    Find-MatchingChildren -Root $prefetch -Aliases $Identity.Aliases -MaxDepth 0

    if ($WithUserFiles) {
        foreach ($personalRoot in @(
            (Join-Path $env:USERPROFILE 'Desktop'),
            (Join-Path $env:USERPROFILE 'Documents'),
            (Join-Path $env:USERPROFILE 'Downloads')
        )) {
            Find-MatchingChildren -Root $personalRoot -Aliases $Identity.Aliases -MaxDepth 4 -Personal $true
        }
    }

    Find-RegistryTraces -Aliases $Identity.Aliases -DeepRegistryTerm $Identity.DeepRegistryTerm -Program $Program
    Find-ServiceAndTaskTraces -Aliases $Identity.Aliases -InstallPaths $Identity.InstallPaths
    return @($script:TraceIndex.Values | Sort-Object Kind, Target, ValueName)
}

function Show-TraceSummary {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces,
        [switch]$ShowAll
    )

    Write-Host ''
    if ($Traces.Count -eq 0) {
        Write-Status (T 'NoTraces') 'Success'
        return
    }

    Write-Host (T 'TracesFound' @($Traces.Count)) -ForegroundColor White
    foreach ($group in @($Traces | Group-Object Kind | Sort-Object Name)) {
        Write-Host ('  {0}: {1}' -f $group.Name, $group.Count)
        $visibleTraces = if ($ShowAll) { @($group.Group) } else { @($group.Group | Select-Object -First 8) }
        foreach ($trace in $visibleTraces) {
            $suffix = if ($trace.ValueName) { ' -> ' + $trace.ValueName } else { '' }
            $personal = if ($trace.Personal) { ' [' + (T 'PersonalFile') + ']' } else { '' }
            Write-Host ('    ' + $trace.Target + $suffix + $personal) -ForegroundColor DarkGray
        }
        if (-not $ShowAll -and $group.Count -gt 8) {
            Write-Host ('    ' + (T 'MoreItems' @(($group.Count - 8)))) -ForegroundColor DarkGray
        }
    }
}

function Read-TraceDeletionConfirmation {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces)
    if ($Traces.Count -eq 0) { return $false }

    Write-Host ''
    Write-Host ('  [1] ' + (T 'DeleteFoundTraces')) -ForegroundColor Red
    Write-Host ('  [2] ' + (T 'KeepFoundTraces'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return $true }
        if ($answer -eq '2') { return $false }
        Write-Status (T 'InvalidTraceDelete') 'Warning'
    }
}

function New-RestorePointIfPossible {
    param([Parameter(Mandatory = $true)][string]$ProgramName)

    if ($NoRestorePoint) {
        Write-Status (T 'RestoreSkipped') 'Warning'
        return $true
    }
    try {
        Checkpoint-Computer -Description ('Vor Entfernung von ' + $ProgramName) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Status (T 'RestorePointDone') 'Success'
        return $true
    }
    catch {
        Write-Status (T 'RestorePointFailed') 'Error'
        Write-Status (T 'RestoreBlocked') 'Error'
        if (-not $script:InteractiveSession) { return $false }
        Write-Host ('  [1] ' + (T 'RestoreAbort'))
        Write-Host ('  [2] ' + (T 'RestoreContinue')) -ForegroundColor Red
        while ($true) {
            $answer = (Read-Host (T 'SelectPrompt')).Trim()
            if ($answer -eq '1') { return $false }
            if ($answer -eq '2') { return $true }
            Write-Status (T 'InvalidRestore') 'Warning'
        }
    }
}

function Invoke-SelectedUninstall {
    param(
        [Parameter(Mandatory = $true)][object]$Program,
        [bool]$RemoveProvisioned = $false
    )

    if ($Program.Type -eq 'Appx') {
        $script:ProvisionedRemovedCount = 0
        Write-Status (T 'StoreRemoving' @($Program.DisplayName))
        Remove-AppxPackage -Package $Program.PackageFullName -ErrorAction Stop
        if ($RemoveProvisioned) {
            $packageName = [string]$Program.PackageName
            $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
                $_.DisplayName -eq $packageName -or $_.PackageName -like ($packageName + '_*')
            })
            foreach ($package in $provisioned) {
                Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                $script:ProvisionedRemovedCount++
            }
            Write-Status (T 'AppxProvisionedDone' @($script:ProvisionedRemovedCount)) 'Success'
        }
        return
    }

    $commandLine = if ($Program.QuietUninstallString) { $Program.QuietUninstallString } else { $Program.UninstallString }
    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        throw 'Das Programm besitzt kein verwendbares Deinstallationskommando.'
    }

    $guid = ''
    foreach ($candidate in @($Program.ProductCode, $commandLine)) {
        if ([string]$candidate -match '\{[0-9A-Fa-f-]{36}\}') { $guid = $matches[0]; break }
    }

    if ($guid) {
        $file = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $arguments = '/x ' + $guid + ' /qn /norestart'
    }
    else {
        $split = Split-CommandLine -CommandLine $commandLine
        $file = $split[0]
        $arguments = $split[1]
    }

    if (-not (Test-Path -LiteralPath $file)) {
        $resolvedCommand = Get-Command -Name $file -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolvedCommand) {
            $file = $resolvedCommand.Source
        }
        else {
            throw ('Deinstallationsprogramm nicht gefunden: ' + $file)
        }
    }

    Write-Status (T 'UninstallRunning' @($Program.DisplayName))
    $process = Start-Process -FilePath $file -ArgumentList $arguments -Wait -PassThru
    $accepted = @(0, 1605, 1614, 1641, 3010)
    if ($accepted -notcontains $process.ExitCode) {
        throw ('Die Deinstallation meldete Exitcode ' + $process.ExitCode + '.')
    }
    if ($process.ExitCode -in @(1641, 3010)) { $script:RestartRequired = $true }
    Write-Status (T 'UninstallDone') 'Success'
}

function Remove-RegistryTrace {
    param([Parameter(Mandatory = $true)][object]$Trace)

    if (Test-ProtectedRegistryKey -RegistryPath $Trace.Target) {
        throw ('Geschützter Registrierungspfad wurde blockiert: ' + $Trace.Target)
    }

    if ($Trace.Kind -eq 'RegistryKey') {
        & reg.exe delete $Trace.Target /f 2>$null | Out-Null
        if ($LASTEXITCODE -notin @(0, 1)) { throw ('Registry-Schlüssel konnte nicht gelöscht werden: ' + $Trace.Target) }
        return
    }

    $defaultNames = @('(Default)', '(Standard)', '<NO NAME>')
    if ($defaultNames -contains $Trace.ValueName) {
        & reg.exe delete $Trace.Target /ve /f 2>$null | Out-Null
    }
    else {
        & reg.exe delete $Trace.Target /v $Trace.ValueName /f 2>$null | Out-Null
    }
    if ($LASTEXITCODE -notin @(0, 1)) { throw ('Registry-Wert konnte nicht gelöscht werden: ' + $Trace.Target + ' -> ' + $Trace.ValueName) }
}

function Remove-Traces {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces)

    $removed = 0
    $failed = New-Object System.Collections.Generic.List[string]

    # Untergeordnete Registry-Werte entfallen automatisch, wenn der Schlüssel gelöscht wird.
    $keyTargets = @($Traces | Where-Object Kind -eq 'RegistryKey' | ForEach-Object { $_.Target.TrimEnd('\') })
    $ordered = @($Traces | Sort-Object @{
        Expression = {
            switch ($_.Kind) {
                'Service' { 0 }
                'Task' { 1 }
                'RegistryValue' { 2 }
                'RegistryKey' { 3 }
                'File' { 4 }
                'Directory' { 5 }
                default { 9 }
            }
        }
    })

    foreach ($trace in $ordered) {
        try {
            if ($trace.Kind -eq 'RegistryValue') {
                $covered = @($keyTargets | Where-Object { $trace.Target.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) -or $trace.Target.Equals($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
                if ($covered) { continue }
            }

            switch ($trace.Kind) {
                'File' {
                    if (-not (Test-ProtectedFilePath -Path $trace.Target) -and (Test-Path -LiteralPath $trace.Target)) {
                        Remove-Item -LiteralPath $trace.Target -Force -ErrorAction Stop
                    }
                }
                'Directory' {
                    if (-not (Test-ProtectedFilePath -Path $trace.Target) -and (Test-Path -LiteralPath $trace.Target)) {
                        Remove-Item -LiteralPath $trace.Target -Recurse -Force -ErrorAction Stop
                    }
                }
                'RegistryKey' { Remove-RegistryTrace -Trace $trace }
                'RegistryValue' { Remove-RegistryTrace -Trace $trace }
                'Service' {
                    $service = Get-Service -Name $trace.Target -ErrorAction SilentlyContinue
                    if ($service) {
                        if ($service.Status -ne 'Stopped') { Stop-Service -Name $trace.Target -Force -ErrorAction SilentlyContinue }
                        & sc.exe delete $trace.Target | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw ('Dienst konnte nicht gelöscht werden: ' + $trace.Target) }
                    }
                }
                'Task' {
                    $lastSlash = $trace.Target.LastIndexOf('\')
                    $taskPath = if ($lastSlash -ge 0) { $trace.Target.Substring(0, $lastSlash + 1) } else { '\' }
                    $taskName = if ($lastSlash -ge 0) { $trace.Target.Substring($lastSlash + 1) } else { $trace.Target }
                    Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            $removed++
        }
        catch {
            $failed.Add($trace.Target + ' :: ' + $_.Exception.Message)
        }
    }

    return [PSCustomObject]@{ Removed = $removed; Failed = $failed.ToArray() }
}

function Save-RunLog {
    param(
        [AllowNull()][object]$Program,
        [Parameter(Mandatory = $true)][string]$SearchName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces,
        [AllowNull()][object]$Result
    )

    try {
        $logRoot = $script:LogRoot
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeName = (Normalize-Text $SearchName)
        if (-not $safeName) { $safeName = 'programm' }
        $base = Join-Path $logRoot ($stamp + '-' + $safeName)

        $manifest = [PSCustomObject]@{
            CleanerVersion = $script:CleanerVersion
            Timestamp      = (Get-Date).ToString('o')
            Computer       = $env:COMPUTERNAME
            SearchName     = $SearchName
            Selected       = $Program
            IncludeUserFiles = [bool]$IncludeUserFiles
            DryRun         = [bool]$DryRun
            Traces         = $Traces
            Result         = $Result
        }
        $manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath ($base + '.json') -Encoding UTF8
        $script:LogLines | Set-Content -LiteralPath ($base + '.log') -Encoding UTF8
        return ($base + '.json')
    }
    catch {
        Write-Status (T 'LogSaveError' @($_.Exception.Message)) 'Warning'
        return ''
    }
}

function Save-ToolLog {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [AllowNull()][object]$Data
    )

    try {
        New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
        $safeAction = (Normalize-Text $Action)
        if (-not $safeAction) { $safeAction = 'tool' }
        $path = Join-Path $script:LogRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $safeAction + '.json')
        [PSCustomObject]@{
            CleanerVersion = $script:CleanerVersion
            Timestamp      = [DateTimeOffset]::Now.ToString('o')
            Computer       = $env:COMPUTERNAME
            Action         = $Action
            Data           = $Data
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
    catch {
        Write-Status (T 'LogSaveError' @($_.Exception.Message)) 'Warning'
        return ''
    }
}

function Test-SystemIntegrity {
    $checks = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $serviceRules = @(
        [PSCustomObject]@{ Name = 'wuauserv'; Display = 'Windows Update'; MustRun = $false },
        [PSCustomObject]@{ Name = 'BITS'; Display = 'Background Intelligent Transfer Service'; MustRun = $false },
        [PSCustomObject]@{ Name = 'WinDefend'; Display = 'Microsoft Defender Antivirus'; MustRun = $true },
        [PSCustomObject]@{ Name = 'SecurityHealthService'; Display = 'Windows Security Health'; MustRun = $true },
        [PSCustomObject]@{ Name = 'InstallService'; Display = 'Microsoft Store Install Service'; MustRun = $false }
    )

    Write-Host ''
    Write-Host (T 'IntegrityTitle') -ForegroundColor White
    foreach ($rule in $serviceRules) {
        $service = Get-CimInstance Win32_Service -Filter ("Name='" + $rule.Name + "'") -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            $state = 'Missing'
            $startMode = 'Unknown'
            $healthy = $false
        }
        else {
            $state = [string]$service.State
            $startMode = [string]$service.StartMode
            $healthy = ($startMode -ne 'Disabled') -and (-not $rule.MustRun -or $state -eq 'Running')
        }
        $check = [PSCustomObject]@{
            Type      = 'Service'
            Name      = $rule.Name
            Display   = $rule.Display
            State     = $state
            StartMode = $startMode
            Healthy   = [bool]$healthy
        }
        $checks.Add($check)
        Write-Host ('  ' + (T 'IntegrityLine' @($rule.Display, $state, $startMode))) -ForegroundColor $(if ($healthy) { 'Green' } else { 'Yellow' })
        if (-not $healthy) { $warnings.Add($rule.Display + ': ' + $state + '/' + $startMode) }
    }

    try {
        $defender = Get-MpComputerStatus -ErrorAction Stop
        $defenderHealthy = [bool]$defender.AntivirusEnabled -and [bool]$defender.RealTimeProtectionEnabled
        $checks.Add([PSCustomObject]@{
            Type = 'DefenderStatus'; Name = 'Get-MpComputerStatus'; Display = 'Microsoft Defender';
            State = $(if ($defenderHealthy) { 'Enabled' } else { 'Not fully enabled' }); StartMode = ''; Healthy = $defenderHealthy
        })
        if (-not $defenderHealthy) { $warnings.Add('Microsoft Defender: Antivirus or real-time protection is not enabled') }
    }
    catch {
        $checks.Add([PSCustomObject]@{
            Type = 'DefenderStatus'; Name = 'Get-MpComputerStatus'; Display = 'Microsoft Defender';
            State = 'Unavailable'; StartMode = ''; Healthy = $false
        })
        $warnings.Add('Microsoft Defender status unavailable')
    }

    $result = [PSCustomObject]@{
        Timestamp = [DateTimeOffset]::Now.ToString('o')
        Passed    = ($warnings.Count -eq 0)
        Warnings  = $warnings.ToArray()
        Checks    = $checks.ToArray()
    }
    if ($result.Passed) {
        Write-Status (T 'IntegrityHealthy') 'Success'
    }
    else {
        Write-Status (T 'IntegrityWarnings' @($warnings.Count)) 'Warning'
    }
    return $result
}

function Read-IntegrityCheckChoice {
    if ($TestIntegrity) { return $true }
    if (-not $script:InteractiveSession) { return $false }
    Write-Host ''
    Write-Host (T 'IntegrityQuestion') -ForegroundColor White
    Write-Host ('  [1] ' + (T 'IntegrityRun'))
    Write-Host ('  [2] ' + (T 'IntegritySkip'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return $true }
        if ($answer -eq '2') { return $false }
        Write-Status (T 'InvalidOneTwo') 'Warning'
    }
}

function Invoke-SystemIntegrityScreen {
    Clear-Host
    Show-BrandHeader
    $result = Test-SystemIntegrity
    $logPath = Save-ToolLog -Action 'SystemIntegrity' -Data $result
    if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Get-RemovalHistory {
    if (-not (Test-Path -LiteralPath $script:HistoryPath)) { return @() }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-Content -LiteralPath $script:HistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entries.Add(($line | ConvertFrom-Json -DateKind String)) } catch { }
    }
    return @($entries | Sort-Object Timestamp -Descending)
}

function Add-RemovalHistory {
    param(
        [Parameter(Mandatory = $true)][string]$ProgramName,
        [bool]$ResidualMode,
        [int]$RemovedCount,
        [int]$FailedCount,
        [int]$RemainingCount,
        [int64]$FreedBytes = 0,
        [AllowEmptyString()][string]$LogPath
    )

    try {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        $entry = [PSCustomObject]@{
            Id              = [Guid]::NewGuid().ToString('N')
            Timestamp       = [DateTimeOffset]::Now.ToString('o')
            ProgramName     = $ProgramName
            Mode            = $(if ($ResidualMode) { 'ResidualOnly' } else { 'Uninstall' })
            RemovedTraces   = $RemovedCount
            FailedTraces    = $FailedCount
            RemainingTraces = $RemainingCount
            FreedBytes       = $FreedBytes
            RestartRequired = [bool]$script:RestartRequired
            Status          = $(if ($FailedCount -eq 0 -and $RemainingCount -eq 0) { 'Complete' } else { 'Warnings' })
            LogPath         = $LogPath
        }
        ($entry | ConvertTo-Json -Compress -Depth 4) |
            Add-Content -LiteralPath $script:HistoryPath -Encoding UTF8
    }
    catch {
        Write-Status (T 'HistorySaveError' @($_.Exception.Message)) 'Warning'
    }
}

function Import-HistoryFromExistingLogs {
    if (-not (Test-Path -LiteralPath $script:LogRoot)) { return }

    try {
        $knownLogs = @{}
        foreach ($entry in @(Get-RemovalHistory)) {
            $knownPath = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'LogPath')
            if (-not [string]::IsNullOrWhiteSpace($knownPath)) { $knownLogs[$knownPath] = $true }
        }

        $importedEntries = New-Object System.Collections.Generic.List[object]
        foreach ($file in @(Get-ChildItem -LiteralPath $script:LogRoot -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            if ($knownLogs.ContainsKey($file.FullName)) { continue }
            try {
                $manifest = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
                $wasDryRun = [bool](Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'DryRun')
                $result = Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'Result'
                if ($wasDryRun -or $null -eq $result -or $result -eq '') { continue }

                $programName = [string](Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'SearchName')
                if ([string]::IsNullOrWhiteSpace($programName)) { continue }
                if ($programName -like 'CodexCleanerFixture*') { continue }
                $timestamp = [string](Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'Timestamp')
                if ([string]::IsNullOrWhiteSpace($timestamp)) { $timestamp = $file.LastWriteTime.ToString('o') }
                $removed = [int](Get-OptionalPropertyValue -InputObject $result -PropertyName 'Removed')
                $failed = @((Get-OptionalPropertyValue -InputObject $result -PropertyName 'Failed')).Count
                $selected = Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'Selected'

                $importedEntries.Add([PSCustomObject]@{
                    Id              = [Guid]::NewGuid().ToString('N')
                    Timestamp       = $timestamp
                    ProgramName     = $programName
                    Mode            = $(if ($null -eq $selected -or $selected -eq '') { 'ResidualOnly' } else { 'Uninstall' })
                    RemovedTraces   = $removed
                    FailedTraces    = $failed
                    RemainingTraces = 0
                    FreedBytes       = [int64](Get-OptionalPropertyValue -InputObject $result -PropertyName 'FreedBytes')
                    RestartRequired = $false
                    Status          = $(if ($failed -eq 0) { 'Complete' } else { 'Warnings' })
                    LogPath         = $file.FullName
                })
            }
            catch { }
        }

        if ($importedEntries.Count -gt 0) {
            New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
            foreach ($entry in $importedEntries) {
                ($entry | ConvertTo-Json -Compress -Depth 4) |
                    Add-Content -LiteralPath $script:HistoryPath -Encoding UTF8
            }
        }
    }
    catch { }
}

function Get-HistoryStatusText {
    param([AllowEmptyString()][string]$Status)
    if ($Status -eq 'Complete') { return (T 'StatusComplete') }
    return (T 'StatusWarnings')
}

function Format-HistoryTimestamp {
    param([AllowEmptyString()][string]$Timestamp)
    try {
        $parsed = [DateTimeOffset]::Parse(
            $Timestamp,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
        return $parsed.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    }
    catch { return $Timestamp }
}

function Show-HistorySummary {
    $history = @(Get-RemovalHistory | Select-Object -First 3)
    Write-Host (T 'HistoryHeading') -ForegroundColor White
    if ($history.Count -eq 0) {
        Write-Host ('  ' + (T 'HistoryNone')) -ForegroundColor DarkGray
    }
    else {
        foreach ($entry in $history) {
            $when = Format-HistoryTimestamp -Timestamp ([string]$entry.Timestamp)
            $status = Get-HistoryStatusText -Status ([string]$entry.Status)
            $line = T 'HistoryLine' @($when, [string]$entry.ProgramName, [int]$entry.RemovedTraces, $status)
            $freed = [int64](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'FreedBytes')
            if ($freed -gt 0) { $line += T 'HistoryFreed' @((Format-ByteSize -Bytes $freed)) }
            Write-Host ('  ' + $line) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

function Read-MainOrExitChoice {
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -in @('1', 'menu', 'm')) { return 'menu' }
        if ($answer -in @('0', 'exit')) { return 'exit' }
        Write-Status (T 'InvalidPost') 'Warning'
    }
}

function Show-HistoryScreen {
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'HistoryTitle') -ForegroundColor White
    Write-Host ''
    $history = @(Get-RemovalHistory)
    if ($history.Count -eq 0) {
        Write-Host (T 'HistoryNone') -ForegroundColor DarkGray
    }
    else {
        $number = 1
        foreach ($entry in @($history | Select-Object -First 100)) {
            $when = Format-HistoryTimestamp -Timestamp ([string]$entry.Timestamp)
            $status = Get-HistoryStatusText -Status ([string]$entry.Status)
            $line = T 'HistoryLine' @($when, [string]$entry.ProgramName, [int]$entry.RemovedTraces, $status)
            $freed = [int64](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'FreedBytes')
            if ($freed -gt 0) { $line += T 'HistoryFreed' @((Format-ByteSize -Bytes $freed)) }
            Write-Host ('  [{0}] {1}' -f $number, $line)
            $number++
        }
    }
    Write-Host ''
    Write-Host ('  [1] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Show-LanguageMenu {
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'LanguageTitle') -ForegroundColor White
    Write-Host (T 'LanguageCurrent' @((Get-LanguageDisplayName -Code $script:Language))) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [1] Deutsch'
    Write-Host '  [2] English'
    Write-Host '  [3] Español'
    Write-Host '  [4] Français'
    Write-Host '  [5] Русский'
    Write-Host '  [6] Türkçe'
    Write-Host ('  [0] ' + (T 'BackMain'))

    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '0') { return }
        $mapping = @{ '1' = 'de'; '2' = 'en'; '3' = 'es'; '4' = 'fr'; '5' = 'ru'; '6' = 'tr' }
        if ($mapping.ContainsKey($answer)) {
            $script:Language = [string]$mapping[$answer]
            Save-AppSettings
            Write-Status (T 'LanguageSaved' @((Get-LanguageDisplayName -Code $script:Language))) 'Success'
            Start-Sleep -Milliseconds 900
            return
        }
        Write-Status (T 'InvalidLanguage') 'Warning'
    }
}

function Show-AdvancedToolsMenu {
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'ToolsTitle') -ForegroundColor White
    Write-Host ''
    Write-Host ('  [1] ' + (T 'Tools1'))
    Write-Host ('  [2] ' + (T 'Tools2'))
    Write-Host ('  [3] ' + (T 'Tools3'))
    Write-Host ('  [4] ' + (T 'Tools4'))
    Write-Host ('  [5] ' + (T 'Tools5'))
    Write-Host ('  [6] ' + (T 'Tools6'))
    Write-Host ('  [0] ' + (T 'BackMain'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -match '^[0-6]$') { return $answer }
        Write-Status (T 'InvalidTools') 'Warning'
    }
}

function Invoke-AntivirusMenu {
    if (-not (Initialize-AntivirusModule)) { return 'menu' }

    :antivirusLoop while ($true) {
        Clear-Host
        Show-BrandHeader
        Write-Host (T 'AVTitle') -ForegroundColor White
        Write-Host ''
        Write-Host ('  [1] ' + (T 'AV1'))
        Write-Host ('  [2] ' + (T 'AV2'))
        Write-Host ('  [3] ' + (T 'AV3'))
        Write-Host ('  [4] ' + (T 'AV4'))
        Write-Host ('  [5] ' + (T 'AV5'))
        Write-Host ('  [6] ' + (T 'AV6'))
        Write-Host ('  [7] ' + (T 'AV7'))
        Write-Host ('  [0] ' + (T 'BackPreviousMenu'))
        $choice = (Read-Host (T 'SelectPrompt')).Trim()
        if ($choice -eq '0') { return 'menu' }
        if ($choice -notmatch '^[1-7]$') {
            Write-Status (T 'InvalidAVChoice') 'Warning'
            Start-Sleep -Milliseconds 800
            continue antivirusLoop
        }

        try {
            switch ($choice) {
                '1' {
                    Get-ClamAVStatus | Format-List Installed, Ready, Version, SignatureDate, SignatureAgeDays, Signatures, SignaturesOutdated, ClamScanPath, FreshClamPath, DatabasePath | Out-Host
                }
                '2' {
                    Initialize-ClamAV -Install -Confirm:$false | Format-List | Out-Host
                }
                '3' {
                    Update-ClamAVEngine -Confirm:$false | Format-List | Out-Host
                }
                '4' {
                    Update-ClamAVSignature | Format-List | Out-Host
                }
                '5' {
                    $results = @(Invoke-ClamAVScan -ScanType Quick)
                    $results | Format-Table Status, Severity, Signature, Path -AutoSize | Out-Host
                }
                '6' {
                    $customPath = (Read-Host (T 'AVPathPrompt')).Trim().Trim('"')
                    if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                        $results = @(Invoke-ClamAVScan -Path $customPath -ScanType Custom)
                        $results | Format-Table Status, Severity, Signature, Path -AutoSize | Out-Host
                    }
                }
                '7' {
                    $entries = @(Get-ClamAVQuarantine)
                    if ($entries.Count -eq 0) {
                        Write-Status (T 'AVNoQuarantine') 'Success'
                    }
                    else {
                        for ($index = 0; $index -lt $entries.Count; $index++) {
                            Write-Host ('  [{0}] {1} | {2} | {3}' -f ($index + 1), $entries[$index].Signature, $entries[$index].QuarantinedAt, $entries[$index].OriginalPath)
                        }
                        $restoreChoice = (Read-Host (T 'AVRestorePrompt')).Trim()
                        $restoreNumber = 0
                        if ([int]::TryParse($restoreChoice, [ref]$restoreNumber) -and $restoreNumber -ge 1 -and $restoreNumber -le $entries.Count) {
                            Restore-FromClamAVQuarantine -Identifier $entries[$restoreNumber - 1].QuarantineId | Format-List | Out-Host
                        }
                    }
                }
            }
        }
        catch {
            Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
        }

        Write-Host ''
        Write-Host ('  [1] ' + (T 'AVReturnMenu'))
        Write-Host ('  [0] ' + (T 'BackMain'))
        while ($true) {
            $afterChoice = (Read-Host (T 'SelectPrompt')).Trim()
            if ($afterChoice -eq '1') { continue antivirusLoop }
            if ($afterChoice -eq '0') { return 'menu' }
            Write-Status (T 'InvalidPost') 'Warning'
        }
    }
}

function Read-ExplicitConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$WarningText,
        [Parameter(Mandatory = $true)][string]$ActionText
    )
    Write-Host ''
    Write-Host $WarningText -ForegroundColor Yellow
    Write-Host ('  [1] ' + $ActionText) -ForegroundColor Red
    Write-Host ('  [2] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return 'start' }
        if ($answer -eq '2') { return 'menu' }
        if ($answer -eq '0') { return 'exit' }
        Write-Status (T 'InvalidConfirm') 'Warning'
    }
}

function Get-OrphanedUninstallEntries {
    $entries = New-Object System.Collections.Generic.List[object]
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($entry in @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue)) {
        $displayName = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayName')
        if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
        if ([string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'SystemComponent') -eq '1') { continue }

        $uninstall = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'UninstallString')
        $installLocation = [Environment]::ExpandEnvironmentVariables([string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'InstallLocation'))
        if ([string]::IsNullOrWhiteSpace($uninstall) -and [string]::IsNullOrWhiteSpace($installLocation)) { continue }

        $validLocation = (-not [string]::IsNullOrWhiteSpace($installLocation)) -and (Test-Path -LiteralPath $installLocation)
        $validUninstaller = $false
        $uninstallExecutable = Get-ExecutableFromCommandLine -CommandLine $uninstall
        if (-not [string]::IsNullOrWhiteSpace($uninstallExecutable)) {
            $validUninstaller = Test-Path -LiteralPath $uninstallExecutable
            if (-not $validUninstaller) {
                $validUninstaller = $null -ne (Get-Command -Name $uninstallExecutable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
            }
        }
        if ($uninstall -match '(?i)msiexec(\.exe)?\s+[/\\][xXiI]\s*\{[0-9A-F-]{36}\}') { $validUninstaller = $true }
        if ($validLocation -or $validUninstaller) { continue }

        $candidate = [PSCustomObject]@{
            Type = 'OrphanRegistry'; SourceLabel = 'Registry'; DisplayName = $displayName
            DisplayVersion = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayVersion')
            Publisher = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'Publisher')
            InstallLocation = $installLocation; InstallSource = ''; UninstallString = $uninstall
            QuietUninstallString = ''; RegistryPath = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSPath')
            ProductCode = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSChildName')
            PackageFullName = ''; PackageName = ''; IsSystemLike = $false; CanUninstall = $true
        }
        if ($null -eq (Get-ProtectedComponentMatch -Program $candidate -SearchName $displayName)) { $entries.Add($candidate) }
    }
    return @($entries | Sort-Object DisplayName, RegistryPath -Unique)
}

function Invoke-OrphanRegistryMenu {
    if (-not (Request-ElevationForTool -Mode Registry)) { return 'menu' }
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'OrphanTitle') -ForegroundColor White
    Write-Host (T 'OrphanDescription') -ForegroundColor DarkGray
    $entries = @(Get-OrphanedUninstallEntries)
    if ($entries.Count -eq 0) {
        Write-Status (T 'OrphanNone') 'Success'
        Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
        Write-Host ('  [0] ' + (T 'Main0'))
        return (Read-MainOrExitChoice)
    }
    Write-Status (T 'OrphanFound' @($entries.Count)) 'Warning'
    $selected = Select-ProgramPaged -Programs $entries -Title (T 'OrphanTitle')
    if ($script:ExitRequested) { return 'exit' }
    if ($null -eq $selected) { return 'menu' }
    $nativePath = $selected.RegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    Write-Host (T 'RegistryPathLabel' @($nativePath)) -ForegroundColor DarkGray
    $confirmation = Read-ExplicitConfirmation -WarningText (T 'OrphanDescription') -ActionText (T 'OrphanDelete')
    if ($confirmation -ne 'start') { return $confirmation }
    if (-not (New-RestorePointIfPossible -ProgramName $selected.DisplayName)) { return 'menu' }
    try {
        Remove-RegistryTrace -Trace ([PSCustomObject]@{ Kind = 'RegistryKey'; Target = $nativePath; ValueName = '' })
        Write-Status (T 'OrphanDeleted') 'Success'
        $logPath = Save-ToolLog -Action 'OrphanRegistryRemoval' -Data $selected
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    }
    catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Invoke-OptionalFeatureMenu {
    if (-not (Request-ElevationForTool -Mode Features)) { return 'menu' }
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'FeatureTitle') -ForegroundColor White
    try {
        $features = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object State -eq 'Enabled' | ForEach-Object {
            [PSCustomObject]@{
                Type = 'OptionalFeature'; SourceLabel = 'DISM'; DisplayName = [string]$_.FeatureName
                DisplayVersion = ''; Publisher = 'Microsoft'; InstallLocation = ''; InstallSource = ''
                UninstallString = ''; QuietUninstallString = ''; RegistryPath = ''; ProductCode = ''
                PackageFullName = ''; PackageName = ''; IsSystemLike = $false; CanUninstall = $true
            }
        })
    }
    catch {
        Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
        $features = @()
    }
    if ($features.Count -eq 0) {
        Write-Status (T 'FeatureNone') 'Warning'
        Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
        Write-Host ('  [0] ' + (T 'Main0'))
        return (Read-MainOrExitChoice)
    }
    $selected = Select-ProgramPaged -Programs $features -Title (T 'FeatureTitle')
    if ($script:ExitRequested) { return 'exit' }
    if ($null -eq $selected) { return 'menu' }
    if (-not (Confirm-ProtectedComponentOverride -Program $selected -SearchName $selected.DisplayName)) { return 'menu' }
    $warning = T 'FeatureWarning' @($selected.DisplayName)
    $confirmation = Read-ExplicitConfirmation -WarningText $warning -ActionText $warning
    if ($confirmation -ne 'start') { return $confirmation }
    if (-not (New-RestorePointIfPossible -ProgramName $selected.DisplayName)) { return 'menu' }
    try {
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $selected.DisplayName -NoRestart -ErrorAction Stop
        if ([bool]$result.RestartNeeded) { $script:RestartRequired = $true }
        Write-Status (T 'FeatureDisabled' @($selected.DisplayName)) 'Success'
        $logPath = Save-ToolLog -Action 'DisableWindowsFeature' -Data ([PSCustomObject]@{ Feature = $selected.DisplayName; RestartNeeded = [bool]$result.RestartNeeded })
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
        if ($script:RestartRequired) { Write-Status (T 'RestartNotice') 'Warning' }
    }
    catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Get-PrivacyRegistryChanges {
    return @(
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Value = 0; Type = 'DWord' }
    )
}

function Save-PrivacyBackupIfNeeded {
    if (Test-Path -LiteralPath $script:PrivacyBackupPath) { return }
    $snapshots = New-Object System.Collections.Generic.List[object]
    foreach ($change in @(Get-PrivacyRegistryChanges)) {
        $key = Get-Item -LiteralPath $change.Path -ErrorAction SilentlyContinue
        $valueObject = if ($key) { Get-ItemProperty -LiteralPath $change.Path -Name $change.Name -ErrorAction SilentlyContinue } else { $null }
        $property = if ($null -ne $valueObject) { $valueObject.PSObject.Properties[$change.Name] } else { $null }
        $existed = $null -ne $property
        $kind = if ($existed) { [string]$key.GetValueKind($change.Name) } else { [string]$change.Type }
        $snapshots.Add([PSCustomObject]@{
            Path = $change.Path; Name = $change.Name; Existed = $existed
            Value = $(if ($existed) { $property.Value } else { $null }); Type = $kind
        })
    }
    $diagTrack = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction SilentlyContinue
    $backup = [PSCustomObject]@{
        Timestamp = [DateTimeOffset]::Now.ToString('o')
        Registry = $snapshots.ToArray()
        DiagTrack = $(if ($diagTrack) { [PSCustomObject]@{ Exists = $true; StartMode = [string]$diagTrack.StartMode; State = [string]$diagTrack.State } } else { [PSCustomObject]@{ Exists = $false; StartMode = ''; State = '' } })
    }
    New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
    $backup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:PrivacyBackupPath -Encoding UTF8
}

function Set-PrivacyProfile {
    Save-PrivacyBackupIfNeeded
    foreach ($change in @(Get-PrivacyRegistryChanges)) {
        New-Item -Path $change.Path -Force | Out-Null
        New-ItemProperty -LiteralPath $change.Path -Name $change.Name -Value $change.Value -PropertyType $change.Type -Force | Out-Null
    }
    $service = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Stopped') { Stop-Service -Name 'DiagTrack' -Force -ErrorAction Stop }
        Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
    }
}

function Restore-PrivacyProfile {
    if (-not (Test-Path -LiteralPath $script:PrivacyBackupPath)) { return $false }
    $backup = Get-Content -LiteralPath $script:PrivacyBackupPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    foreach ($snapshot in @($backup.Registry)) {
        if ([bool]$snapshot.Existed) {
            New-Item -Path ([string]$snapshot.Path) -Force | Out-Null
            New-ItemProperty -LiteralPath ([string]$snapshot.Path) -Name ([string]$snapshot.Name) -Value $snapshot.Value -PropertyType ([string]$snapshot.Type) -Force | Out-Null
        }
        elseif (Test-Path -LiteralPath ([string]$snapshot.Path)) {
            Remove-ItemProperty -LiteralPath ([string]$snapshot.Path) -Name ([string]$snapshot.Name) -ErrorAction SilentlyContinue
        }
    }
    if ([bool]$backup.DiagTrack.Exists) {
        $startupType = switch ([string]$backup.DiagTrack.StartMode) { 'Auto' { 'Automatic' }; 'Manual' { 'Manual' }; 'Disabled' { 'Disabled' }; default { 'Manual' } }
        Set-Service -Name 'DiagTrack' -StartupType $startupType -ErrorAction SilentlyContinue
        if ([string]$backup.DiagTrack.State -eq 'Running') { Start-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $script:PrivacyBackupPath -Force -ErrorAction Stop
    return $true
}

function Invoke-PrivacyMenu {
    if (-not (Request-ElevationForTool -Mode Privacy)) { return 'menu' }
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'PrivacyTitle') -ForegroundColor White
    Write-Host (T 'PrivacyDescription') -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Service: DiagTrack -> Stopped / Disabled' -ForegroundColor DarkGray
    foreach ($change in @(Get-PrivacyRegistryChanges)) {
        Write-Host ('  {0}\{1} = {2}' -f $change.Path, $change.Name, $change.Value) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host ('  [1] ' + (T 'PrivacyApply'))
    Write-Host ('  [2] ' + (T 'PrivacyRestore'))
    Write-Host ('  [3] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '0') { return 'exit' }
        if ($answer -eq '3') { return 'menu' }
        if ($answer -eq '1') {
            $confirmation = Read-ExplicitConfirmation -WarningText (T 'PrivacyDescription') -ActionText (T 'PrivacyApply')
            if ($confirmation -ne 'start') { return $confirmation }
            if (-not (New-RestorePointIfPossible -ProgramName (T 'PrivacyTitle'))) { return 'menu' }
            try {
                Set-PrivacyProfile
                Write-Status (T 'PrivacyDone') 'Success'
                $logPath = Save-ToolLog -Action 'PrivacyProfileApplied' -Data (Get-PrivacyRegistryChanges)
                if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
            }
            catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
            break
        }
        if ($answer -eq '2') {
            if (-not (Test-Path -LiteralPath $script:PrivacyBackupPath)) {
                Write-Status (T 'PrivacyNoBackup') 'Warning'
                continue
            }
            $confirmation = Read-ExplicitConfirmation -WarningText (T 'PrivacyRestore') -ActionText (T 'PrivacyRestore')
            if ($confirmation -ne 'start') { return $confirmation }
            try {
                if (Restore-PrivacyProfile) {
                    Write-Status (T 'PrivacyRestored') 'Success'
                    $logPath = Save-ToolLog -Action 'PrivacyProfileRestored' -Data $null
                    if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
                }
            }
            catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
            break
        }
        Write-Status (T 'InvalidPrivacyChoice') 'Warning'
    }
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Invoke-LogCleanupMenu {
    :logCleanupLoop while ($true) {
    Clear-Host
    Show-BrandHeader
    Write-Host (T 'LogsTitle') -ForegroundColor White
    Write-Host ''

    $logFiles = @()
    if (Test-Path -LiteralPath $script:LogRoot) {
        $logFiles = @(Get-ChildItem -LiteralPath $script:LogRoot -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @('.json', '.log')
        })
    }

    if ($logFiles.Count -eq 0) {
        Write-Host (T 'LogsNone') -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ('  [1] ' + (T 'BackMain'))
        Write-Host ('  [0] ' + (T 'Main0'))
        return (Read-MainOrExitChoice)
    }

    Write-Host (T 'LogsCount' @($logFiles.Count))
    Write-Host ('  [1] ' + (T 'LogsDelete')) -ForegroundColor Yellow
    Write-Host ('  [2] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))

    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -in @('0', 'exit')) { return 'exit' }
        if ($answer -in @('2', 'menu', 'm')) { return 'menu' }
        if ($answer -eq '1') {
            $deleted = 0
            $failed = 0
            foreach ($file in $logFiles) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $deleted++
                }
                catch { $failed++ }
            }
            Write-Status (T 'LogsDeleted' @($deleted)) 'Success'
            if ($failed -gt 0) { Write-Status (T 'LogsFailed' @($failed)) 'Warning' }
            Write-Host ''
            Write-Host ('  [1] ' + (T 'LogsTitle'))
            Write-Host ('  [0] ' + (T 'BackPreviousMenu'))
            while ($true) {
                $afterChoice = (Read-Host (T 'SelectPrompt')).Trim()
                if ($afterChoice -eq '1') { continue logCleanupLoop }
                if ($afterChoice -eq '0') { return 'menu' }
                Write-Status (T 'InvalidPost') 'Warning'
            }
        }
        Write-Status (T 'InvalidLogs') 'Warning'
    }
    }
}

function Get-StableIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return -join @($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    }
    finally { $sha.Dispose() }
}

function Test-StartupItemProtected {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Command,
        [AllowEmptyString()][string]$TaskPath = ''
    )

    if ($TaskPath.StartsWith('\Microsoft\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($null -ne (Get-ProtectedComponentMatch -Program $null -SearchName ($Name + ' | ' + $Command))) { return $true }
    if ($Command -match '(?i)\\Windows\\System32\\(SecurityHealth|UsoClient|MusNotification|MoUsoCoreWorker|WaaSMedic|smartscreen)') { return $true }
    return $false
}

function Get-StartupItems {
    $items = New-Object System.Collections.Generic.List[object]
    $registryLocations = @(
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Benutzer'; RequiresAdmin = $false },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Benutzer (einmalig)'; RequiresAdmin = $false },
        [PSCustomObject]@{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Computer'; RequiresAdmin = $true },
        [PSCustomObject]@{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Computer (einmalig)'; RequiresAdmin = $true },
        [PSCustomObject]@{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Computer (32-Bit)'; RequiresAdmin = $true },
        [PSCustomObject]@{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Computer (32-Bit, einmalig)'; RequiresAdmin = $true }
    )

    foreach ($location in $registryLocations) {
        try {
            if (-not (Test-Path -LiteralPath $location.Path)) { continue }
            $key = Get-Item -LiteralPath $location.Path -ErrorAction Stop
            foreach ($valueName in @($key.GetValueNames())) {
                if ([string]::IsNullOrWhiteSpace($valueName)) { continue }
                $value = $key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $command = if ($value -is [Array]) { $value -join '; ' } else { [string]$value }
                $id = Get-StableIdentifier -Value ('Registry|' + $location.Path + '|' + $valueName)
                $items.Add([PSCustomObject]@{
                    Id = $id; Name = $valueName; SourceType = 'Registry'; Scope = $location.Scope
                    Command = $command; Location = $location.Path; RequiresAdmin = [bool]$location.RequiresAdmin
                    IsProtected = (Test-StartupItemProtected -Name $valueName -Command $command)
                    RegistryPath = $location.Path; ValueName = $valueName; Value = $value
                    ValueKind = $key.GetValueKind($valueName).ToString(); FilePath = ''; TaskName = ''; TaskPath = ''
                })
            }
        }
        catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Inventory' }
    }

    $startupFolders = @(
        [PSCustomObject]@{ Path = [Environment]::GetFolderPath('Startup'); Scope = 'Benutzer'; RequiresAdmin = $false },
        [PSCustomObject]@{ Path = [Environment]::GetFolderPath('CommonStartup'); Scope = 'Alle Benutzer'; RequiresAdmin = $true }
    )
    foreach ($folder in $startupFolders) {
        try {
            if ([string]::IsNullOrWhiteSpace($folder.Path) -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $folder.Path -File -Force -ErrorAction Stop)) {
                if ($file.Name -ieq 'desktop.ini') { continue }
                $id = Get-StableIdentifier -Value ('File|' + $file.FullName)
                $items.Add([PSCustomObject]@{
                    Id = $id; Name = $file.BaseName; SourceType = 'StartupFolder'; Scope = $folder.Scope
                    Command = $file.FullName; Location = $folder.Path; RequiresAdmin = [bool]$folder.RequiresAdmin
                    IsProtected = (Test-StartupItemProtected -Name $file.BaseName -Command $file.FullName)
                    RegistryPath = ''; ValueName = ''; Value = $null; ValueKind = ''; FilePath = $file.FullName
                    TaskName = ''; TaskPath = ''
                })
            }
        }
        catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Inventory' }
    }

    try {
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            foreach ($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
                $_.State -ne 'Disabled' -and @($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }).Count -gt 0
            })) {
                $command = @($task.Actions | ForEach-Object { (($_.Execute + ' ' + $_.Arguments).Trim()) }) -join ' | '
                $id = Get-StableIdentifier -Value ('Task|' + $task.TaskPath + '|' + $task.TaskName)
                $items.Add([PSCustomObject]@{
                    Id = $id; Name = $task.TaskName; SourceType = 'ScheduledTask'; Scope = 'Geplante Aufgabe'
                    Command = $command; Location = $task.TaskPath; RequiresAdmin = $true
                    IsProtected = (Test-StartupItemProtected -Name $task.TaskName -Command $command -TaskPath $task.TaskPath)
                    RegistryPath = ''; ValueName = ''; Value = $null; ValueKind = ''; FilePath = ''
                    TaskName = $task.TaskName; TaskPath = $task.TaskPath
                })
            }
        }
    }
    catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Inventory' }

    return @($items | Sort-Object Name, SourceType, Scope)
}

function Save-StartupManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [AllowEmptyString()][string]$Path = ''
    )

    New-Item -ItemType Directory -Path $script:StartupBackupRoot -Force | Out-Null
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $script:StartupBackupRoot ([string]$Manifest.BackupId + '.json')
    }
    $copy = $Manifest.PSObject.Copy()
    if ($copy.PSObject.Properties['_ManifestPath']) { $copy.PSObject.Properties.Remove('_ManifestPath') }
    $copy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Add-StartupHistory {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][bool]$Succeeded,
        [AllowEmptyString()][string]$Details = ''
    )

    try {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        [PSCustomObject]@{
            Timestamp = [DateTimeOffset]::Now.ToString('o')
            Action = $Action
            Name = [string]$Item.Name
            SourceType = [string]$Item.SourceType
            Location = [string]$Item.Location
            Command = [string]$Item.Command
            Succeeded = $Succeeded
            Details = $Details
        } | ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $script:StartupHistoryPath -Encoding UTF8
    }
    catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/History' }
}

function Get-StartupHistory {
    if (-not (Test-Path -LiteralPath $script:StartupHistoryPath)) { return @() }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-Content -LiteralPath $script:StartupHistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entries.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return @($entries | Sort-Object Timestamp -Descending)
}

function Get-StartupBackups {
    if (-not (Test-Path -LiteralPath $script:StartupBackupRoot)) { return @() }
    $backups = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $script:StartupBackupRoot -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $entry = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([bool](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'Active')) {
                $entry | Add-Member -NotePropertyName '_ManifestPath' -NotePropertyValue $file.FullName -Force
                $backups.Add($entry)
            }
        }
        catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Backup' }
    }
    return @($backups | Sort-Object DisabledAt -Descending)
}

function Disable-StartupItem {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [switch]$SkipConfirmation
    )

    if ([bool]$Item.IsProtected) {
        Write-Status (T 'StartupProtected') 'Warning'
        return $false
    }
    if (-not $SkipConfirmation) {
        $choice = Read-ExplicitConfirmation -WarningText (T 'StartupConfirm' @([string]$Item.Name)) -ActionText (T 'StartupConfirm' @([string]$Item.Name))
        if ($choice -ne 'start') { return $false }
    }
    if ([bool]$Item.RequiresAdmin -and -not (Test-IsAdministrator)) {
        [void](Request-ElevationForTool -Mode Startup -ItemId ([string]$Item.Id))
        return $false
    }

    $backupId = [Guid]::NewGuid().ToString('N')
    $backupPath = ''
    $manifest = [PSCustomObject]@{
        BackupId = $backupId; Active = $true; DisabledAt = [DateTimeOffset]::Now.ToString('o'); RestoredAt = ''
        Name = [string]$Item.Name; SourceType = [string]$Item.SourceType; Scope = [string]$Item.Scope
        Command = [string]$Item.Command; Location = [string]$Item.Location; RequiresAdmin = [bool]$Item.RequiresAdmin
        RegistryPath = [string]$Item.RegistryPath; ValueName = [string]$Item.ValueName
        Value = $Item.Value; ValueKind = [string]$Item.ValueKind; OriginalFilePath = [string]$Item.FilePath
        BackupFilePath = ''; TaskName = [string]$Item.TaskName; TaskPath = [string]$Item.TaskPath
    }

    try {
        if ($Item.SourceType -eq 'StartupFolder') {
            $fileBackupRoot = Join-Path (Join-Path $script:StartupBackupRoot 'Files') $backupId
            New-Item -ItemType Directory -Path $fileBackupRoot -Force | Out-Null
            $backupPath = Join-Path $fileBackupRoot ([IO.Path]::GetFileName([string]$Item.FilePath))
            $manifest.BackupFilePath = $backupPath
        }
        $manifestPath = Save-StartupManifest -Manifest $manifest

        switch ([string]$Item.SourceType) {
            'Registry' {
                Remove-ItemProperty -LiteralPath ([string]$Item.RegistryPath) -Name ([string]$Item.ValueName) -ErrorAction Stop
            }
            'StartupFolder' {
                Move-Item -LiteralPath ([string]$Item.FilePath) -Destination $backupPath -ErrorAction Stop
            }
            'ScheduledTask' {
                Disable-ScheduledTask -TaskName ([string]$Item.TaskName) -TaskPath ([string]$Item.TaskPath) -ErrorAction Stop | Out-Null
            }
            default { throw "Unbekannter Autostart-Typ: $($Item.SourceType)" }
        }

        Add-StartupHistory -Action 'Disabled' -Item $Item -Succeeded $true -Details $manifestPath
        [void](Save-ToolLog -Action 'StartupDisabled' -Data $manifest)
        Write-Status (T 'StartupDisabled' @([string]$Item.Name)) 'Success'
        return $true
    }
    catch {
        $manifest.Active = $false
        $manifest.RestoredAt = [DateTimeOffset]::Now.ToString('o')
        try { [void](Save-StartupManifest -Manifest $manifest) } catch { }
        Add-StartupHistory -Action 'DisableFailed' -Item $Item -Succeeded $false -Details $_.Exception.Message
        Write-Status (T 'StartupActionFailed' @($_.Exception.Message)) 'Error'
        return $false
    }
}

function Restore-StartupItem {
    param(
        [Parameter(Mandatory = $true)][object]$Backup,
        [switch]$SkipConfirmation
    )

    if (-not $SkipConfirmation) {
        $choice = Read-ExplicitConfirmation -WarningText (T 'StartupRestoreConfirm' @([string]$Backup.Name)) -ActionText (T 'StartupRestoreConfirm' @([string]$Backup.Name))
        if ($choice -ne 'start') { return $false }
    }
    if ([bool]$Backup.RequiresAdmin -and -not (Test-IsAdministrator)) {
        [void](Request-ElevationForTool -Mode Startup -ItemId ('restore:' + [string]$Backup.BackupId))
        return $false
    }

    try {
        switch ([string]$Backup.SourceType) {
            'Registry' {
                if (-not (Test-Path -LiteralPath ([string]$Backup.RegistryPath))) {
                    New-Item -Path ([string]$Backup.RegistryPath) -Force | Out-Null
                }
                $value = $Backup.Value
                switch ([string]$Backup.ValueKind) {
                    'Binary' { $value = [byte[]]@($Backup.Value) }
                    'DWord' { $value = [int]$Backup.Value }
                    'QWord' { $value = [long]$Backup.Value }
                    'MultiString' { $value = [string[]]@($Backup.Value) }
                    default { $value = [string]$Backup.Value }
                }
                New-ItemProperty -LiteralPath ([string]$Backup.RegistryPath) -Name ([string]$Backup.ValueName) -Value $value -PropertyType ([string]$Backup.ValueKind) -Force -ErrorAction Stop | Out-Null
            }
            'StartupFolder' {
                if (-not (Test-Path -LiteralPath ([string]$Backup.BackupFilePath))) { throw 'Die gesicherte Autostart-Datei fehlt.' }
                if (Test-Path -LiteralPath ([string]$Backup.OriginalFilePath)) { throw 'Am ursprünglichen Ort existiert bereits eine Datei mit demselben Namen.' }
                $parent = Split-Path -Parent ([string]$Backup.OriginalFilePath)
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
                Move-Item -LiteralPath ([string]$Backup.BackupFilePath) -Destination ([string]$Backup.OriginalFilePath) -ErrorAction Stop
            }
            'ScheduledTask' {
                Enable-ScheduledTask -TaskName ([string]$Backup.TaskName) -TaskPath ([string]$Backup.TaskPath) -ErrorAction Stop | Out-Null
            }
            default { throw "Unbekannter Autostart-Typ: $($Backup.SourceType)" }
        }

        $Backup.Active = $false
        $Backup.RestoredAt = [DateTimeOffset]::Now.ToString('o')
        [void](Save-StartupManifest -Manifest $Backup -Path ([string]$Backup._ManifestPath))
        Add-StartupHistory -Action 'Restored' -Item $Backup -Succeeded $true -Details ([string]$Backup.BackupId)
        [void](Save-ToolLog -Action 'StartupRestored' -Data $Backup)
        Write-Status (T 'StartupRestored' @([string]$Backup.Name)) 'Success'
        return $true
    }
    catch {
        Add-StartupHistory -Action 'RestoreFailed' -Item $Backup -Succeeded $false -Details $_.Exception.Message
        Write-Status (T 'StartupActionFailed' @($_.Exception.Message)) 'Error'
        return $false
    }
}

function Show-StartupHistoryScreen {
    Clear-Host
    Show-BrandHeader -Section (T 'StartupTitle')
    $history = @(Get-StartupHistory)
    if ($history.Count -eq 0) {
        Write-Host (T 'StartupHistoryNone') -ForegroundColor DarkGray
    }
    else {
        $number = 1
        foreach ($entry in @($history | Select-Object -First 100)) {
            $when = Format-HistoryTimestamp -Timestamp ([string]$entry.Timestamp)
            $state = if ([bool]$entry.Succeeded) { 'OK' } else { 'FEHLER' }
            Write-Host ('  [{0}] {1} | {2} | {3} | {4}' -f $number, $when, $entry.Action, $entry.Name, $state)
            $number++
        }
    }
    Write-Host ''
    Write-Host ('  [0] ' + (T 'BackHome'))
    while ((Read-Host (T 'SelectPrompt')).Trim() -ne '0') { Write-Status (T 'StartupInvalid') 'Warning' }
}

function Invoke-StartupList {
    $page = 0
    :startupListLoop while ($true) {
        Clear-Host
        Show-BrandHeader -Section (T 'StartupTitle')
        Write-Host (T 'StartupDescription') -ForegroundColor DarkGray
        Write-Host ''
        $items = @(Get-StartupItems)
        if ($items.Count -eq 0) {
            Write-Host (T 'StartupNone') -ForegroundColor DarkGray
            Write-Host ('  [0] ' + (T 'BackHome'))
            while ((Read-Host (T 'SelectPrompt')).Trim() -ne '0') { Write-Status (T 'StartupInvalid') 'Warning' }
            return
        }

        $pageSize = 18
        :startupPageLoop while ($true) {
            Clear-Host
            Show-BrandHeader -Section (T 'StartupTitle')
            $pageCount = [Math]::Max(1, [Math]::Ceiling($items.Count / [double]$pageSize))
            if ($page -ge $pageCount) { $page = $pageCount - 1 }
            $start = $page * $pageSize
            $end = [Math]::Min($start + $pageSize - 1, $items.Count - 1)
            Write-Host ('Seite {0}/{1} | Einträge: {2}' -f ($page + 1), $pageCount, $items.Count) -ForegroundColor DarkGray
            Write-Host ''
            for ($index = $start; $index -le $end; $index++) {
                $item = $items[$index]
                $flag = if ($item.IsProtected) { ' | geschützt' } elseif ($item.RequiresAdmin) { ' | Admin' } else { '' }
                Write-Host ('  [{0}] {1} | {2} | {3}{4}' -f ($index + 1), $item.Name, $item.SourceType, $item.Scope, $flag)
                Write-Host ('       ' + $item.Command) -ForegroundColor DarkGray
            }
            Write-Host ''
            Write-Host (T 'StartupSelect') -ForegroundColor DarkGray
            Write-Host '  [-1] nächste Seite | [-2] vorherige Seite | [0] zurück' -ForegroundColor DarkGray
            $answer = (Read-Host (T 'SelectPrompt')).Trim()
            if ($answer -eq '0') { return }
            if ($answer -eq '-1') { if ($page + 1 -lt $pageCount) { $page++ }; continue startupPageLoop }
            if ($answer -eq '-2') { if ($page -gt 0) { $page-- }; continue startupPageLoop }
            $number = 0
            if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $items.Count) {
                $selected = $items[$number - 1]
                if (Disable-StartupItem -Item $selected) { Start-Sleep -Milliseconds 900 }
                continue startupListLoop
            }
            Write-Status (T 'StartupInvalid') 'Warning'
            Start-Sleep -Milliseconds 800
        }
    }
}

function Invoke-StartupRestoreList {
    :startupRestoreLoop while ($true) {
    Clear-Host
    Show-BrandHeader -Section (T 'StartupTitle')
    $backups = @(Get-StartupBackups)
    if ($backups.Count -eq 0) {
        Write-Host (T 'StartupBackupsNone') -ForegroundColor DarkGray
        Write-Host ('  [0] ' + (T 'BackHome'))
        while ((Read-Host (T 'SelectPrompt')).Trim() -ne '0') { Write-Status (T 'StartupInvalid') 'Warning' }
        return
    }
    for ($index = 0; $index -lt $backups.Count; $index++) {
        $when = Format-HistoryTimestamp -Timestamp ([string]$backups[$index].DisabledAt)
        Write-Host ('  [{0}] {1} | {2} | {3}' -f ($index + 1), $when, $backups[$index].Name, $backups[$index].SourceType)
    }
    Write-Host ('  [0] ' + (T 'BackHome'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '0') { return }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $backups.Count) {
            [void](Restore-StartupItem -Backup $backups[$number - 1])
            Start-Sleep -Milliseconds 900
            continue startupRestoreLoop
        }
        Write-Status (T 'StartupInvalid') 'Warning'
    }
    }
}

function Invoke-StartupMenu {
    param([AllowEmptyString()][string]$InitialActionId = '')

    if (-not [string]::IsNullOrWhiteSpace($InitialActionId)) {
        if ($InitialActionId.StartsWith('restore:', [StringComparison]::OrdinalIgnoreCase)) {
            $backupId = $InitialActionId.Substring(8)
            $backup = @(Get-StartupBackups | Where-Object { $_.BackupId -eq $backupId } | Select-Object -First 1)
            if ($backup.Count -eq 1) { [void](Restore-StartupItem -Backup $backup[0] -SkipConfirmation) }
        }
        else {
            $item = @(Get-StartupItems | Where-Object { $_.Id -eq $InitialActionId } | Select-Object -First 1)
            if ($item.Count -eq 1) { [void](Disable-StartupItem -Item $item[0] -SkipConfirmation) }
        }
    }

    :startupMenuLoop while ($true) {
        Clear-Host
        Show-BrandHeader -Section (T 'StartupTitle')
        Write-Host (T 'StartupDescription') -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ('  [1] ' + (T 'Startup1'))
        Write-Host ('  [2] ' + (T 'Startup2'))
        Write-Host ('  [3] ' + (T 'Startup3'))
        Write-Host ('  [0] ' + (T 'BackHome'))
        $choice = (Read-Host (T 'SelectPrompt')).Trim()
        switch ($choice) {
            '0' { return 'menu' }
            '1' { Invoke-StartupList; continue startupMenuLoop }
            '2' { Invoke-StartupRestoreList; continue startupMenuLoop }
            '3' { Show-StartupHistoryScreen; continue startupMenuLoop }
            default { Write-Status (T 'InvalidStartupMenu') 'Warning'; Start-Sleep -Milliseconds 700 }
        }
    }
}

function Invoke-ActiveServicesScreen {
    try {
        $allServices = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
            Where-Object { $_.State -eq 'Running' } |
            Sort-Object DisplayName, Name)
    }
    catch {
        Write-Status (T 'ServicesReadError' @($_.Exception.Message)) 'Error'
        return 'menu'
    }

    $filter = ''
    $page = 0
    $pageSize = 20
    while ($true) {
        $services = if ([string]::IsNullOrWhiteSpace($filter)) {
            $allServices
        }
        else {
            @($allServices | Where-Object { $_.DisplayName -like ('*' + $filter + '*') -or $_.Name -like ('*' + $filter + '*') })
        }
        $pageCount = [Math]::Max(1, [Math]::Ceiling($services.Count / [double]$pageSize))
        if ($page -ge $pageCount) { $page = $pageCount - 1 }
        Clear-Host
        Show-BrandHeader -Section (T 'ServicesTitle')
        Write-Host (T 'ServicesDescription') -ForegroundColor DarkGray
        if ($filter) { Write-Host (T 'FilterLabel' @($filter)) -ForegroundColor Yellow }
        Write-Host (T 'ServicesPage' @(($page + 1), $pageCount, $services.Count)) -ForegroundColor DarkGray
        Write-Host ''
        if ($services.Count -eq 0) {
            Write-Host (T 'ServicesNone') -ForegroundColor DarkGray
        }
        else {
            $start = $page * $pageSize
            $end = [Math]::Min($start + $pageSize - 1, $services.Count - 1)
            for ($index = $start; $index -le $end; $index++) {
                $service = $services[$index]
                Write-Host ('  [{0}] {1} [{2}] | Start: {3} | PID: {4}' -f ($index + 1), $service.DisplayName, $service.Name, $service.StartMode, $service.ProcessId)
            }
        }
        Write-Host ''
        Write-Host (T 'ServicesCommands') -ForegroundColor DarkGray
        $choice = (Read-Host (T 'SelectPrompt')).Trim()
        switch ($choice) {
            '0' { return 'menu' }
            '1' { if ($page + 1 -lt $pageCount) { $page++ } }
            '2' { if ($page -gt 0) { $page-- } }
            '3' { $filter = (Read-Host (T 'SearchPrompt')).Trim(); $page = 0 }
            '4' { $filter = ''; $page = 0 }
            default { Write-Status (T 'StartupInvalid') 'Warning'; Start-Sleep -Milliseconds 700 }
        }
    }
}

function Read-RemovalConfirmation {
    param([Parameter(Mandatory = $true)][string]$ProgramName)
    Write-Host ''
    Write-Host (T 'Selected' @($ProgramName)) -ForegroundColor White
    Write-Host (T 'RemovalWarning') -ForegroundColor Yellow
    if ($IncludeUserFiles) {
        Write-Host (T 'PersonalWarning') -ForegroundColor Red
    }
    Write-Host ('  [1] ' + (T 'ConfirmStart'))
    Write-Host ('  [2] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))

    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -in @('1', 'ent')) { return 'start' }
        if ($answer -in @('2', 'menu', 'm')) { return 'menu' }
        if ($answer -in @('0', 'exit')) { return 'exit' }
        Write-Status (T 'InvalidConfirm') 'Warning'
    }
}

function Read-AppxRemovalScope {
    Write-Host ''
    Write-Host (T 'AppxScopeQuestion') -ForegroundColor White
    Write-Host ('  [1] ' + (T 'AppxCurrentOnly'))
    Write-Host ('  [2] ' + (T 'AppxProvisioned')) -ForegroundColor Yellow
    Write-Host ('  [3] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $answer = (Read-Host (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return 'current' }
        if ($answer -eq '2') { return 'provisioned' }
        if ($answer -eq '3') { return 'menu' }
        if ($answer -eq '0') { return 'exit' }
        Write-Status (T 'InvalidAppxScope') 'Warning'
    }
}

function Invoke-RemovalOperation {
    param(
        [Parameter(Mandatory = $true)][string]$OperationName,
        [bool]$OperationResidualOnly,
        [bool]$OperationDryRun,
        [AllowNull()][object]$PreselectedProgram,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$PreloadedPrograms,
        [bool]$SkipConfirmation,
        [bool]$ContinueAfterElevation,
        [AllowEmptyString()][string]$ExpectedRegistryPath,
        [AllowEmptyString()][string]$ExpectedPackageFullName
    )

    # Lokale Variablen gleichen Namens sorgen dafür, dass Protokoll- und Hilfsfunktionen
    # innerhalb dieses Durchlaufs die tatsächlich gewählten Optionen sehen.
    $Name = $OperationName.Trim()
    $script:LastRunLogPath = ''
    $ResidualOnly = $OperationResidualOnly
    $DryRun = $OperationDryRun
    $programs = @($PreloadedPrograms)
    $selected = $PreselectedProgram
    $removeProvisionedForRun = [bool]$RemoveProvisionedAppx
    $antivirusBeforeResults = @()
    $antivirusAfterResults = @()

    Set-OperationProgress -Percent 1 -Status (T 'ProgressPrepare')

    if ((-not [string]::IsNullOrWhiteSpace($ExpectedRegistryPath)) -or
        (-not [string]::IsNullOrWhiteSpace($ExpectedPackageFullName))) {
        Set-OperationProgress -Percent 5 -Status (T 'ProgressRecheck')
        if ($programs.Count -eq 0) { $programs = @(Get-InstalledPrograms) }

        $exactMatches = @($programs | Where-Object {
            ((-not [string]::IsNullOrWhiteSpace($ExpectedRegistryPath)) -and $_.RegistryPath -eq $ExpectedRegistryPath) -or
            ((-not [string]::IsNullOrWhiteSpace($ExpectedPackageFullName)) -and $_.PackageFullName -eq $ExpectedPackageFullName)
        })
        if ($exactMatches.Count -ne 1) {
            throw 'Die zuvor ausgewählte Anwendung konnte nach der Administratorfreigabe nicht eindeutig wiedergefunden werden. Es wurde nichts entfernt.'
        }
        $selected = $exactMatches[0]
        $Name = $selected.DisplayName
    }

    if ($null -eq $selected -and -not $ResidualOnly) {
        if ($programs.Count -eq 0) {
            Set-OperationProgress -Percent 5 -Status (T 'ProgressInventory')
            $programs = @(Get-InstalledPrograms)
        }
        $candidates = @(Find-ProgramCandidates -Programs $programs -SearchName $Name)

        if ($candidates.Count -gt 0) {
            $selected = Select-Program -Candidates $candidates
            if ($null -eq $selected) {
                Write-Status (T 'SelectionCancelled') 'Warning'
                Complete-OperationProgress
                return $false
            }
            $Name = $selected.DisplayName
        }
        else {
            Write-Status (T 'NoProgramFound' @($Name)) 'Warning'
            Write-Host (T 'ResidualQuestion') -ForegroundColor White
            Write-Host ('  [1] ' + (T 'YesResidual'))
            Write-Host ('  [2] ' + (T 'BackMain'))
            Write-Host ('  [0] ' + (T 'Main0'))
            while ($true) {
                $answer = (Read-Host (T 'SelectPrompt')).Trim()
                if ($answer -in @('1', 'j', 'ja', 'y', 'yes')) {
                    $ResidualOnly = $true
                    break
                }
                if ($answer -in @('2', 'menu', 'm')) {
                    Complete-OperationProgress
                    return $false
                }
                if ($answer -in @('0', 'exit')) {
                    $script:ExitRequested = $true
                    Complete-OperationProgress
                    return $false
                }
                Write-Status (T 'InvalidConfirm') 'Warning'
            }
        }
    }

    if (-not $DryRun -and -not (Confirm-ProtectedComponentOverride -Program $selected -SearchName $Name)) {
        Write-Status (T 'SelectionCancelled') 'Warning'
        Complete-OperationProgress
        return $false
    }

    Set-OperationProgress -Percent 10 -Status (T 'ProgressIdentity')
    $identity = Get-IdentityInfo -SearchName $Name -Program $selected
    Write-Status (T 'SafeTerms' @(($identity.Aliases -join ', ')))
    Write-Status (T 'DeepSearch')
    Set-OperationProgress -Percent 15 -Status (T 'ProgressSearch')
    $traces = @(Find-AllTraces -Identity $identity -Program $selected -WithUserFiles ([bool]$IncludeUserFiles))
    $initialTraceCount = $traces.Count
    Set-OperationProgress -Percent 30 -Status (T 'ProgressPreview')
    Show-TraceSummary -Traces $traces -ShowAll

    if ($DryRun) {
        Write-Status (T 'DryRunDone') 'Success'
        $logPath = Save-RunLog -Program $selected -SearchName $Name -Traces $traces -Result $null
        $script:LastRunLogPath = [string]$logPath
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
        Set-OperationProgress -Percent 100 -Status (T 'ProgressDryDone')
        Complete-OperationProgress
        return $true
    }

    $displayName = if ($null -ne $selected) { $selected.DisplayName } else { T 'ResidualSuffix' @($Name) }
    if (-not $SkipConfirmation) {
        if ($null -ne $selected -and $selected.Type -eq 'Appx') {
            $scope = Read-AppxRemovalScope
            if ($scope -eq 'exit') {
                $script:ExitRequested = $true
                Complete-OperationProgress
                return $false
            }
            if ($scope -eq 'menu') {
                Complete-OperationProgress
                return $false
            }
            $removeProvisionedForRun = $scope -eq 'provisioned'
        }
        $confirmation = Read-RemovalConfirmation -ProgramName $displayName
        if ($confirmation -eq 'exit') {
            $script:ExitRequested = $true
            Complete-OperationProgress
            return $false
        }
        if ($confirmation -ne 'start') {
            Write-Status (T 'SelectionCancelled') 'Warning'
            Complete-OperationProgress
            return $false
        }
    }

    if (-not (Request-ElevationForRemoval -SearchName $Name -Program $selected -IsResidualOnly $ResidualOnly -ContinueSession $ContinueAfterElevation -ProtectedOverride ([bool]$OverrideProtectedComponent) -ProvisionedAppx $removeProvisionedForRun)) {
        Complete-OperationProgress
        return $false
    }

    Set-OperationProgress -Percent 35 -Status (T 'ProgressBackup')
    if (-not (New-RestorePointIfPossible -ProgramName $displayName)) {
        Complete-OperationProgress
        return $false
    }
    $freeBefore = Get-SystemDriveFreeBytes

    $antivirusBeforeResults = @(Invoke-ConfiguredAntivirusScan -Stage Before -Identity $identity -Traces $traces)

    if ($null -ne $selected) {
        Set-OperationProgress -Percent 40 -Status (T 'ProgressUninstall')
        Invoke-SelectedUninstall -Program $selected -RemoveProvisioned $removeProvisionedForRun
        Start-Sleep -Seconds 2
    }
    Set-OperationProgress -Percent 60 -Status (T 'ProgressUninstallDone')

    # Nach der regulären Deinstallation erneut suchen, da manche Deinstaller neue Logs hinterlassen.
    Write-Status (T 'RescanMessage')
    Set-OperationProgress -Percent 65 -Status (T 'ProgressRescan')
    $traces = @(Find-AllTraces -Identity $identity -Program $selected -WithUserFiles ([bool]$IncludeUserFiles))
    Set-OperationProgress -Percent 75 -Status (T 'ProgressRescanDone')
    Show-TraceSummary -Traces $traces -ShowAll
    $antivirusAfterResults = @(Invoke-ConfiguredAntivirusScan -Stage After -Identity $identity -Traces $traces)
    $deleteTraces = $false
    if ($traces.Count -gt 0 -and $script:InteractiveSession) {
        $deleteTraces = Read-TraceDeletionConfirmation -Traces $traces
    }
    if ($deleteTraces) {
        Set-OperationProgress -Percent 78 -Status (T 'ProgressRemove')
        $result = Remove-Traces -Traces $traces
    }
    else {
        $result = [PSCustomObject]@{ Removed = 0; Failed = @() }
        if ($traces.Count -gt 0) { Write-Status (T 'KeepFoundTraces') 'Warning' }
    }
    Set-OperationProgress -Percent 88 -Status (T 'ProgressCleanupDone')
    Write-Status (T 'RemovedCount' @($result.Removed)) 'Success'

    if ($result.Failed.Count -gt 0) {
        Write-Status (T 'FailedCount' @($result.Failed.Count)) 'Warning'
        foreach ($failure in $result.Failed) { Write-Host ('  ' + $failure) -ForegroundColor Yellow }
    }

    Write-Status (T 'FinalCheck')
    Set-OperationProgress -Percent 92 -Status (T 'ProgressVerify')
    $remaining = @(Find-AllTraces -Identity $identity -Program $null -WithUserFiles ([bool]$IncludeUserFiles))
    $remaining = @($remaining | Where-Object {
        if ($_.Kind -eq 'RegistryKey' -and $null -ne $selected -and $_.Target -eq ($selected.RegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) {
            return $false
        }
        return $true
    })

    $freeAfter = Get-SystemDriveFreeBytes
    $freedBytes = [int64]0
    if ($freeBefore -ge 0 -and $freeAfter -ge 0) {
        $difference = [int64]($freeAfter - $freeBefore)
        if ($difference -gt 0) {
            $freedBytes = $difference
            Write-Status (T 'StorageFreed' @((Format-ByteSize -Bytes $freedBytes))) 'Success'
        }
        else {
            Write-Status (T 'StorageUnclear') 'Warning'
        }
    }

    $integrityResult = $null
    if (Read-IntegrityCheckChoice) { $integrityResult = Test-SystemIntegrity }
    $result | Add-Member -NotePropertyName FreedBytes -NotePropertyValue $freedBytes -Force
    $result | Add-Member -NotePropertyName ProvisionedAppxRemoved -NotePropertyValue ([int]$script:ProvisionedRemovedCount) -Force
    $result | Add-Member -NotePropertyName IntegrityCheck -NotePropertyValue $integrityResult -Force
    $result | Add-Member -NotePropertyName AntivirusBefore -NotePropertyValue @($antivirusBeforeResults) -Force
    $result | Add-Member -NotePropertyName AntivirusAfter -NotePropertyValue @($antivirusAfterResults) -Force

    $logPath = Save-RunLog -Program $selected -SearchName $Name -Traces $traces -Result $result
    $script:LastRunLogPath = [string]$logPath
    if ($remaining.Count -eq 0 -and $result.Failed.Count -eq 0) {
        Write-Status (T 'FinishedClean') 'Success'
    }
    else {
        Write-Status (T 'FinishedRemaining' @($remaining.Count)) 'Warning'
        Show-TraceSummary -Traces $remaining
    }

    if ($script:RestartRequired) {
        Write-Status (T 'RestartNotice') 'Warning'
    }
    if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    Add-RemovalHistory -ProgramName $Name -ResidualMode $ResidualOnly -RemovedCount ([int]$result.Removed) -FailedCount $result.Failed.Count -RemainingCount $remaining.Count -FreedBytes $freedBytes -LogPath $logPath
    $script:LastRunSummary = [PSCustomObject]@{ Before = $initialTraceCount; Found = $traces.Count; Removed = [int]$result.Removed; Failed = $result.Failed.Count; Remaining = $remaining.Count; Integrity = $integrityResult }
    Set-OperationProgress -Percent 100 -Status (T 'ProgressDone')
    Complete-OperationProgress
    return $true
}

function Invoke-RemnexaSelfTest {
    $checks = New-Object System.Collections.Generic.List[object]
    $addCheck = {
        param([string]$Name, [bool]$Passed, [string]$Details)
        $checks.Add([PSCustomObject]@{ Name = $Name; Passed = $Passed; Details = $Details })
    }

    & $addCheck 'Brand' ($script:BrandName -eq 'REMNEXA' -and $script:CleanerVersion -eq '2.1.3') "$($script:BrandName) $($script:CleanerVersion)"
    foreach ($requiredPath in @(
        (Join-Path $PSScriptRoot 'runtime\pwsh.exe'),
        (Join-Path $PSScriptRoot 'Antivirus\Antivirus.psd1'),
        (Join-Path $PSScriptRoot 'config\antivirus.json'),
        (Join-Path $PSScriptRoot 'assets\remnexa-logo.png')
    )) {
        & $addCheck ('Datei: ' + [IO.Path]::GetFileName($requiredPath)) (Test-Path -LiteralPath $requiredPath -PathType Leaf) $requiredPath
    }

    try {
        $startupCount = @(Get-StartupItems).Count
        & $addCheck 'Autostart-Inventar' $true ("{0} aktive Einträge lesbar" -f $startupCount)
    }
    catch { & $addCheck 'Autostart-Inventar' $false $_.Exception.Message }

    try {
        $serviceCount = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | Where-Object { $_.State -eq 'Running' }).Count
        & $addCheck 'Dienste-Inventar' $true ("{0} aktive Dienste lesbar" -f $serviceCount)
    }
    catch { & $addCheck 'Dienste-Inventar' $false $_.Exception.Message }

    try {
        if (-not (Initialize-AntivirusModule)) { throw 'Antivirus-Modul konnte nicht geladen werden.' }
        $avStatus = Get-ClamAVStatus
        & $addCheck 'ClamAV' ([bool]$avStatus.Installed) ("Version {0}; Signaturen: {1}" -f $avStatus.Version, $avStatus.Signatures)
    }
    catch { & $addCheck 'ClamAV' $false $_.Exception.Message }

    $failed = @($checks | Where-Object { -not $_.Passed }).Count
    return [PSCustomObject]@{
        Application = $script:BrandName
        Version = $script:CleanerVersion
        Timestamp = [DateTimeOffset]::Now.ToString('o')
        Passed = ($failed -eq 0)
        FailedChecks = $failed
        Checks = $checks.ToArray()
    }
}

function Main {
    Initialize-AppSettings
    [void](Initialize-AntivirusModule)
    $interactiveSession = (([string]::IsNullOrWhiteSpace($Name) -and -not $ResidualOnly -and -not $DryRun) -or $ContinueInteractive)
    $script:InteractiveSession = [bool]$interactiveSession
    $hasProvidedRequest = -not [string]::IsNullOrWhiteSpace($Name)
    $currentWorkspace = if ($hasProvidedRequest) { 'Uninstall' } elseif ([string]::IsNullOrWhiteSpace($WorkspaceMode)) { 'Home' } else { $WorkspaceMode }

    if (-not [string]::IsNullOrWhiteSpace($ToolMode)) {
        $toolResult = switch ($ToolMode) {
            'Registry' { Invoke-OrphanRegistryMenu }
            'Features' { Invoke-OptionalFeatureMenu }
            'Privacy'  { Invoke-PrivacyMenu }
            'Antivirus' { Invoke-AntivirusMenu }
            'Startup' { Invoke-StartupMenu -InitialActionId $SelectedStartupId }
        }
        if ($toolResult -eq 'exit' -or -not $ContinueInteractive) { return }
        $currentWorkspace = 'Home'
    }

    :mainLoop while ($true) {
        $script:RestartRequired = $false
        $script:ExitRequested = $false
        Clear-Host
        Show-BrandHeader

        if ($interactiveSession -and -not $hasProvidedRequest -and $currentWorkspace -ne 'Uninstall') {
            switch ($currentWorkspace) {
                'Antivirus' {
                    if ((Invoke-AntivirusMenu) -eq 'exit') { return }
                    $currentWorkspace = 'Home'
                    continue mainLoop
                }
                'Startup' {
                    if ((Invoke-StartupMenu) -eq 'exit') { return }
                    $currentWorkspace = 'Home'
                    continue mainLoop
                }
                'Services' {
                    [void](Invoke-ActiveServicesScreen)
                    $currentWorkspace = 'Home'
                    continue mainLoop
                }
                default {
                    Show-HistorySummary
                    $homeChoice = Show-HomeMenu
                    switch ($homeChoice) {
                        '0' {
                            Write-Status (T 'ProgramEnded') 'Success'
                            return
                        }
                        '1' { $currentWorkspace = 'Uninstall'; continue mainLoop }
                        '2' { $currentWorkspace = 'Antivirus'; continue mainLoop }
                        '3' { $currentWorkspace = 'Startup'; continue mainLoop }
                        '4' { $currentWorkspace = 'Services'; continue mainLoop }
                        '5' {
                            if ((Show-HistoryScreen) -eq 'exit') { return }
                            continue mainLoop
                        }
                        '6' {
                            if ((Invoke-LogCleanupMenu) -eq 'exit') { return }
                            continue mainLoop
                        }
                        '7' {
                            Show-LanguageMenu
                            continue mainLoop
                        }
                        '8' {
                            :homeToolsLoop while ($true) {
                                $homeToolChoice = Show-AdvancedToolsMenu
                                switch ($homeToolChoice) {
                                    '0' { continue mainLoop }
                                    '1' { if ((Invoke-SystemIntegrityScreen) -eq 'exit') { return }; continue homeToolsLoop }
                                    '2' {
                                        Write-Status 'AppX/UWP befindet sich im Deinstallationsbereich unter [9] > [2].' 'Info'
                                        Start-Sleep -Milliseconds 1200
                                        $currentWorkspace = 'Uninstall'
                                        continue mainLoop
                                    }
                                    '3' { if ((Invoke-OrphanRegistryMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                    '4' { if ((Invoke-OptionalFeatureMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                    '5' { if ((Invoke-PrivacyMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                    '6' { if ((Invoke-AntivirusMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                }
                            }
                        }
                    }
                }
            }
        }

        Write-Host (T 'AppDescription')
        if (-not (Test-IsAdministrator)) {
            Write-Host (T 'AdminDeferred') -ForegroundColor DarkGray
        }
        Write-Host ''

        $operationName = ''
        $operationResidualOnly = $false
        $operationDryRun = $false
        $preselected = $null
        $preloadedPrograms = @()
        $skipConfirmation = $false
        $expectedRegistryPath = ''
        $expectedPackageFullName = ''

        if ($hasProvidedRequest) {
            $operationName = $Name
            $operationResidualOnly = [bool]$ResidualOnly
            $operationDryRun = [bool]$DryRun
            $skipConfirmation = [bool]$ResumeRemoval
            $expectedRegistryPath = $SelectedRegistryPath
            $expectedPackageFullName = $SelectedPackageFullName
            $hasProvidedRequest = $false
        }
        elseif ($interactiveSession) {
            Show-HistorySummary
            if ($script:ReturnToProgramList -and $null -ne $script:LastProgramListContext) {
                $menuChoice = '99'
                $preselected = Select-ProgramPaged -Programs $script:LastProgramListContext.Programs -Title $script:LastProgramListContext.Title -ResumeContext $script:LastProgramListContext
                $script:ReturnToProgramList = $false
                if ($script:ExitRequested) { return }
                if ($null -eq $preselected) { continue mainLoop }
            }
            else { $menuChoice = Show-UninstallMenu }
            if ($menuChoice -eq '0') {
                $currentWorkspace = 'Home'
                continue mainLoop
            }

            switch ($menuChoice) {
                '99' { $operationName = $preselected.DisplayName }
                '1' {
                    $operationName = Read-Host (T 'ProgramNamePrompt')
                }
                '2' {
                    Write-Status (T 'InventoryReading')
                    $preloadedPrograms = @(Get-InstalledPrograms)
                    $ordinaryPrograms = @($preloadedPrograms | Where-Object { -not $_.IsSystemLike -and $_.CanUninstall })
                    $preselected = Select-ProgramPaged -Programs $ordinaryPrograms -Title (T 'InstalledTitle')
                    if ($script:ExitRequested) { return }
                    if ($null -eq $preselected) { continue mainLoop }
                    $operationName = $preselected.DisplayName
                }
                '3' {
                    Write-Status (T 'InventoryAllReading')
                    $preloadedPrograms = @(Get-InstalledPrograms)
                    $preselected = Select-ProgramPaged -Programs $preloadedPrograms -Title (T 'AllAppsTitle')
                    if ($script:ExitRequested) { return }
                    if ($null -eq $preselected) { continue mainLoop }
                    $operationName = $preselected.DisplayName
                }
                '4' {
                    $operationName = Read-Host (T 'ResidualNamePrompt')
                    $operationResidualOnly = $true
                }
                '5' {
                    $operationName = Read-Host (T 'DryRunNamePrompt')
                    $operationDryRun = $true
                }
                '6' {
                    if ((Show-HistoryScreen) -eq 'exit') {
                        Write-Status (T 'ProgramEnded') 'Success'
                        return
                    }
                    continue mainLoop
                }
                '7' {
                    if ((Invoke-LogCleanupMenu) -eq 'exit') {
                        Write-Status (T 'ProgramEnded') 'Success'
                        return
                    }
                    continue mainLoop
                }
                '8' {
                    Show-LanguageMenu
                    continue mainLoop
                }
                '9' {
                    $startAppxRemoval = $false
                    :uninstallToolsLoop while ($true) {
                        $toolChoice = Show-AdvancedToolsMenu
                        switch ($toolChoice) {
                            '0' { $currentWorkspace = 'Home'; continue mainLoop }
                            '1' { if ((Invoke-SystemIntegrityScreen) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '2' {
                                Write-Status (T 'InventoryReading')
                                $preloadedPrograms = @(Get-InstalledPrograms)
                                $appxPrograms = @($preloadedPrograms | Where-Object { $_.Type -eq 'Appx' -and -not $_.IsSystemLike -and $_.CanUninstall })
                                $preselected = Select-ProgramPaged -Programs $appxPrograms -Title (T 'AppxTitle')
                                if ($script:ExitRequested) { return }
                                if ($null -eq $preselected) { continue uninstallToolsLoop }
                                $operationName = $preselected.DisplayName
                                $startAppxRemoval = $true
                            }
                            '3' { if ((Invoke-OrphanRegistryMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '4' { if ((Invoke-OptionalFeatureMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '5' { if ((Invoke-PrivacyMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '6' { if ((Invoke-AntivirusMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                        }
                        if ($startAppxRemoval) { break }
                    }
                    if (-not $startAppxRemoval) { continue mainLoop }
                }
            }
        }
        else {
            return
        }

        if ([string]::IsNullOrWhiteSpace($operationName)) {
            Write-Status (T 'NoName') 'Warning'
            if ($interactiveSession) {
                Start-Sleep -Milliseconds 900
                continue mainLoop
            }
            return
        }

        try {
            $completed = Invoke-RemovalOperation `
                -OperationName $operationName `
                -OperationResidualOnly $operationResidualOnly `
                -OperationDryRun $operationDryRun `
                -PreselectedProgram $preselected `
                -PreloadedPrograms $preloadedPrograms `
                -SkipConfirmation $skipConfirmation `
                -ContinueAfterElevation $interactiveSession `
                -ExpectedRegistryPath $expectedRegistryPath `
                -ExpectedPackageFullName $expectedPackageFullName
        }
        catch {
            Complete-OperationProgress
            Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
            Save-RunLog -Program $preselected -SearchName $operationName -Traces @() -Result $null | Out-Null
            $completed = $true
        }

        if ($script:ExitRequested) { return }
        if (-not $interactiveSession) { return }
        if (-not $completed) { continue mainLoop }

        Show-LastRunDetails
        $nextAction = Read-AfterOperationChoice
        if ($nextAction -eq 'list') { $script:ReturnToProgramList = $true }
        if ($nextAction -eq 'exit') {
            Write-Status (T 'ProgramEnded') 'Success'
            return
        }
    }
}

$scriptExitCode = 0
try {
    if ($SelfTest) {
        $selfTestResult = Invoke-RemnexaSelfTest
        $selfTestResult | ConvertTo-Json -Depth 6
        if (-not $selfTestResult.Passed) { $scriptExitCode = 1 }
    }
    else {
        Main
    }
}
catch {
    Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
    Save-RunLog -Program $null -SearchName $(if ($Name) { $Name } else { 'unbekannt' }) -Traces @() -Result $null | Out-Null
    $scriptExitCode = 1
}
Complete-OperationProgress

exit $scriptExitCode

