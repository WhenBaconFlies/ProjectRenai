class_name ChunkConfig
extends Resource

## ChunkConfig
##
## Tunable radii and tick rates for ticket 019's tiered NPC simulation. This is a
## plain Resource so a future Options UI (deferred surface feature) can author and
## swap one at runtime, and so headless tests can construct deterministic configs
## without touching project.godot. ChunkManager falls back to `ChunkConfig.new()`
## when its exported `config` slot is empty.
##
## Radii are Chebyshev distances in chunks (same metric ticket 020 uses for
## renderer chunk load/unload). Tick rates are seconds between simulated NPC
## steps; 0 means "every frame".

## Chebyshev chunk radius inside which NPCs are `close` (full sim + full render).
@export var close_radius_chunks: int = 2

## Chebyshev chunk radius inside which NPCs are `near` (reduced tick rate).
## Clamped to at least `close_radius_chunks` when read by ChunkManager.
@export var near_radius_chunks: int = 4

## Extra chunks of hysteresis: demote only beyond the outer radius + buffer.
@export var hysteresis_chunks: int = 1

## Seconds spent interpolating a promoted NPC's visual position from its coarse
## position to its authoritative position. 0 disables interpolation.
@export var promotion_duration_sec: float = 0.5

## Seconds between close-tier NPC ticks. 0 = every frame.
@export var close_tick_sec: float = 0.0

## Seconds between near-tier NPC ticks. 0 = every frame.
@export var near_tick_sec: float = 0.25

## Seconds between far-tier NPC ticks (with the full accumulated dt).
@export var far_tick_sec: float = 5.0

## Pixel size of one chunk when no Map is attached (headless tests / pre-spawn).
@export var fallback_chunk_pixel_size: int = 512

## Hide far-tier NPC nodes (far = no render, per the chunk-loading plan).
@export var hide_far_npcs: bool = true


## Plain-Dictionary view for diagnostics and round-trip tests.
func to_dictionary() -> Dictionary:
	return {
		"close_radius_chunks": close_radius_chunks,
		"near_radius_chunks": near_radius_chunks,
		"hysteresis_chunks": hysteresis_chunks,
		"promotion_duration_sec": promotion_duration_sec,
		"close_tick_sec": close_tick_sec,
		"near_tick_sec": near_tick_sec,
		"far_tick_sec": far_tick_sec,
		"fallback_chunk_pixel_size": fallback_chunk_pixel_size,
		"hide_far_npcs": hide_far_npcs,
	}
