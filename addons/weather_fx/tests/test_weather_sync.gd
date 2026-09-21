extends GutTest

## Purpose: the host's weather and biome reach every peer through a MultiplayerSynchronizer under the WeatherFX node
## carrying synced_weather and synced_biome, with no RPC of a world's own. A client takes the weather as forced,
## since its own forecast would otherwise overrule it, and takes the biome only when it is not reading it off the
## zones around a target of its own. Two scene branches each get their own MultiplayerAPI and talk over ENet on
## localhost, the way a Steam session does at the high level.

const PORT: int = 47393

var server_root: Node3D
var client_root: Node3D
var server_api: SceneMultiplayer
var client_api: SceneMultiplayer


## One branch: a WeatherFX starting clear, with the synchronizer a world puts under it.
func _build_branch(root: Node3D) -> WeatherFX:
	var weather: WeatherFX = WeatherFX.new()
	weather.name = "WeatherFX"
	weather.blend_zones = false
	weather.set_weather(ClimateData.WeatherType.BLUE_SKY) # the forecast is random: start both sides the same
	root.add_child(weather)
	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for property: NodePath in [^".:synced_biome", ^".:synced_weather"]:
		config.add_property(property)
		config.property_set_spawn(property, true)
		config.property_set_replication_mode(property, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "WeatherSynchronizer"
	sync.replication_config = config
	weather.add_child(sync)
	return weather


func before_each() -> void:
	server_root = Node3D.new()
	server_root.name = "ServerBranch"
	client_root = Node3D.new()
	client_root.name = "ClientBranch"
	add_child(server_root)
	add_child(client_root)
	server_api = SceneMultiplayer.new()
	client_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PORT), OK, "ENet server should open on localhost")
	server_api.multiplayer_peer = server_peer
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PORT), OK)
	client_api.multiplayer_peer = client_peer
	_build_branch(server_root)
	_build_branch(client_root)
	for i: int in 120:
		await wait_process_frames(1)
		if client_api.get_peers().size() > 0 and server_api.get_peers().size() > 0:
			break
	assert_gt(client_api.get_peers().size(), 0, "Client should connect to the loopback server")


func after_each() -> void:
	# Free the branches while their APIs still exist so the synchronizers unregister cleanly
	var server_path: NodePath = server_root.get_path()
	var client_path: NodePath = client_root.get_path()
	server_root.free()
	client_root.free()
	server_api.multiplayer_peer.close()
	client_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, server_path)
	get_tree().set_multiplayer(null, client_path)


func test_the_hosts_weather_is_the_clients_weather() -> void:
	var host: WeatherFX = server_root.get_node("WeatherFX")
	var client: WeatherFX = client_root.get_node("WeatherFX")
	assert_false(host.is_puppet(), "The server is the authority")
	assert_true(client.is_puppet(), "and the client is not")
	host.set_weather(ClimateData.WeatherType.STORM)
	assert_eq(host.synced_weather, ClimateData.WeatherType.STORM, "The host writes what it shows")
	await wait_process_frames(20)
	assert_eq(client.active_weather, ClimateData.WeatherType.STORM, "and the client shows it")
	assert_true(client.force_weather, "held as forced weather, so the client's own forecast cannot overrule it")
	host.set_weather(ClimateData.WeatherType.SNOW)
	await wait_process_frames(20)
	assert_eq(client.active_weather, ClimateData.WeatherType.SNOW, "A second change crosses too, so it is not a coincidence of forecasts")


func test_the_biome_follows_unless_the_client_reads_its_own_zones() -> void:
	var host: WeatherFX = server_root.get_node("WeatherFX")
	var client: WeatherFX = client_root.get_node("WeatherFX")
	host.current_biome = ClimateData.BiomeZone.ARCTIC_TUNDRA
	assert_eq(host.synced_biome, ClimateData.BiomeZone.ARCTIC_TUNDRA)
	await wait_process_frames(20)
	assert_eq(client.current_biome, ClimateData.BiomeZone.ARCTIC_TUNDRA, "A client with no target of its own takes the host's biome")
	# Now the client stands in its own zones
	var target: Node3D = Node3D.new()
	client_root.add_child(target)
	client.target_node = target
	client.blend_zones = true
	assert_true(client.is_blending_zones())
	client.current_biome = ClimateData.BiomeZone.DESERT_DUNES # what its zones say
	host.current_biome = ClimateData.BiomeZone.ALPINE_PEAKS
	await wait_process_frames(20)
	assert_eq(client.synced_biome, ClimateData.BiomeZone.ALPINE_PEAKS, "The host's biome still arrives")
	assert_eq(client.current_biome, ClimateData.BiomeZone.DESERT_DUNES, "but the client keeps the one its zones give it")


func test_offline_the_synced_values_just_follow_the_weather() -> void:
	var alone: WeatherFX = WeatherFX.new()
	alone.set_weather(ClimateData.WeatherType.RAIN)
	add_child_autofree(alone)
	assert_false(alone.is_puppet(), "With no session this side is the authority")
	assert_eq(alone.synced_weather, ClimateData.WeatherType.RAIN)
	alone.current_biome = ClimateData.BiomeZone.HUMID_COAST
	assert_eq(alone.synced_biome, ClimateData.BiomeZone.HUMID_COAST)
	alone.synced_weather = ClimateData.WeatherType.SNOW # a write from nowhere: stored, not applied, since there is no authority to obey
	assert_eq(alone.active_weather, ClimateData.WeatherType.RAIN)
