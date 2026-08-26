extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label
@onready var save_quit_button: Button = $Panel/SaveQuitButton
@onready var abandon_button: Button = $Panel/AbandonButton

func _ready() -> void:
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	save_quit_button.pressed.connect(_on_save_quit_pressed)
	abandon_button.pressed.connect(_on_abandon_pressed)

func show_peer_lost(message: String) -> void:
	label.text = message
	panel.visible = true
	get_tree().paused = true

func hide_overlay() -> void:
	panel.visible = false
	get_tree().paused = false

# Même logique que SettingsOverlay._quit_without_saving() : seul l'hôte écrit
# sur disque (dépositaire unique du fichier multi), un simple client se
# contente de se déconnecter. Cet écran n'apparaît que sur une run
# multijoueur déjà en cours, donc pas besoin de re-tester run_peer_ids.size().
func _on_save_quit_pressed() -> void:
	hide_overlay()
	if NetworkManager.is_host():
		RunManager.save_multi_run_to_disk()
	NetworkManager.close_connection()
	RunManager.reset_run_state()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

# Supprime la sauvegarde partagée quand c'est l'hôte qui abandonne : lui seul
# possède le fichier, donc lui seul peut réellement mettre fin à la run pour
# tout le monde. Un simple client qui abandonne ici ne fait que se
# déconnecter (host toujours dépositaire, run toujours reprenable pour ceux
# qui restent) — cf. décision utilisateur : pas de RPC de suppression à
# distance depuis un client.
func _on_abandon_pressed() -> void:
	hide_overlay()
	if NetworkManager.is_host():
		RunManager.delete_multi_save()
	NetworkManager.close_connection()
	RunManager.reset_run_state()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
