\[Overview]
This game is called Project Renai. It is to be developed in Godot, a blank workspace already exists in the project directory. It is to be a 2D  3/4 view game where the main idea is to simulate a variety of characters living out an ordinary school life with a specific focus on romantic relationships and interacting character traits. For the architecture of the game, modularity is very important in all aspects, for example this means that in the files new characters are saved to a file that can be dragged and dropped to work on someone else's game, same for maps as well, which will be customizable, and also allowing for modding to allow others to create things such as new objects or mechanics and place them in a separate mods folder. The UI should be simple but cute. Code should all be well documented with comments describing what functions or scripts do. This file includes ideas for the baseline of the game.


\[Flow / Main Menu]
The game opens to a main menu with buttons for starting a new game, loading up a saved game, opening the creation menu, opening the mods menu, opening the game options, and closing the game.

\[New Game]
When selecting to start a new game, the player should first be prompted to choose a map. The game should be shipped with multiple maps later, but for now there will be a testing map. After map selection, the save options should appear, prompting the player what options they want that are specific to this save, such as: number of npcs, stat settings, schedule changes, etc. Then on the next page the player will choose their character or be able to create a new one using the same controls as the create menu. Then the player will start playing the game.

\[Load Game]
When selecting load game, the player will get simple options to load previously saved games or delete them.



\[Create Menu]

The create menu has options for creating characters or maps. Selecting a character allows for a wide variety of customization including name, appearance, and lots of traits. Appearance can be selected by mix and match hairs, eyes, mouths, etc. Traits determine how a character can react. By default a character has limited trait points but this can be turned off, positive points take away trait points, negative ones add. These traits come in various selections such as skills, interests, dislikes, and personality. These traits can affect your starting stats and stat growth such as strength, dexterity, constitution, intelligence, wisdom, and charisma. The other create option is the map editor. The map editor gives the players a build menu to freely place down walls, furniture, floors, stairs, and more in an open editor in order to build the school layout, this is saved to its own file as well.

\[Mods Menu]
When opening the mods menu the player should be able to see currently installed and enabled mods. Mods should be pulled from a centralized mod folder and be able to edit various parts of the game.

\[Options Menu]
The player should be given control over various game-wide options, such as volume, language, and resolution.



\[Gameplay]
The actual gameplay of the game. After the player selects their character and starts the game their character will appear at the school entrance and start their first day. Overall, there is a set calender schedule for the school year which the player will play through day by day. Progress can be saved at the end of every day. There is also a day to day schedule for what classes the player should go to and free time. Lots of students and teachers are being simulated at once all with their own stats, goals, and statuses. Interaction is the main idea here where each character with each other and with the player all have familiarity/affection meters, which determine whether they interact as strangers, friends, enemies, lovers, or more. Depending on how outgoing someone is, they may be more or less likely to attempt to talk to someone they don't know, for example. The days are fairly short overall, and class time is mostly skipped, but time remains for plenty of interactions to occur, the main purpose of the game. When interacting with someone, you are given a small randomized pool of options to talk about, depending on factors such as mood, interests, traits, and familiarity. The gameplay is pretty open world with no clear end goal, but there is a time limit of the school year(s). This is just the initial gameplay draft, more is planned to be added on later, but this should contain most of the core components.

