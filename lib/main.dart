import 'dart:math';
import 'dart:convert';


import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:build_a_story/models/completed_section.dart';
import 'package:build_a_story/widgets/completed_section_widget.dart';
import 'package:build_a_story/widgets/video_player.dart';

const String stabiltyEngineId = "stable-diffusion-512-v2-1";
const String stabilityApiHost = "https://api.stability.ai";

const List<String> artStyleOptions = [
  "retro",
  "futuristic",
  "impressionistic",
  "anime",
  "cartoony"
];

const List<String> initialChoiceOptions = [
  "A rabbit enters a wormhole",
  "A knight enters a castle",
  "Batman flies across the city",
  "A scientist discovers time travel",
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  if (kIsWeb) {
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: dotenv.env["FIREBASE_KEY"]!,
            appId: dotenv.env["APP_ID"]!,
            messagingSenderId: dotenv.env["MESSAGING_SENDER_ID"]!,
            projectId: dotenv.env["PROJECT_ID"]!,
            storageBucket: dotenv.env["STORAGE_BUCKET"]!));
  } else {
    await Firebase.initializeApp();
  }

  runApp(const MainApp());
}



class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  List<CompletedSection> completedSections = [];
  String? curStory;
  String? curImage;
  String? previousChoice;
  String? videoUrl;
  List<String>? curChoices;
  int selectedChoiceIndex = 0;
  bool startGenerating = false;
  bool allSectionsCompleted = false;
  bool buildStory = false;
  int chosenArtStyleIndex = 0;
  String? systemDirective;

  Future<String> getChatResponse() async {
    systemDirective ??= await rootBundle.loadString("system_directive.txt");
    late List messages;
    if (completedSections.isEmpty) {
      String initialChoice =
          initialChoiceOptions[Random().nextInt(initialChoiceOptions.length)];
      messages = [
        {"role": "system", "content": systemDirective},
        {"role": "user", "content": initialChoice},
      ];
      previousChoice = initialChoice;
    } else {
      messages = [
        {"role": "system", "content": systemDirective}
      ];
      for (final section in completedSections) {
        messages.add({"role": "user", "content": section.previousChoice});
        messages.add({
          "role": "assistant",
          "content":
              "Story: ${section.storyText}\nChoice1: ${section.choices[0]}\nChoice2: ${section.choices[1]}\nChoice3: End the story"
        });
      }

      messages.add({"role": "user", "content": previousChoice});
    }
    final response =
        await http.post(Uri.parse("https://api.openai.com/v1/chat/completions"),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer ${dotenv.env["OPENAI_KEY"]!}",
            },
            body: jsonEncode({"model": "gpt-3.5-turbo", "messages": messages}));
    String res = json.decode(response.body)["choices"][0]["message"]["content"];
    if (previousChoice != "End the story") {
      curStory = res
          .substring(res.indexOf("Story:") + "Story:".length,
              res.indexOf("Choice1:") - 1)
          .trim();
      String choice1 = res
          .substring(res.indexOf("Choice1:") + "Choice1:".length,
              res.indexOf("Choice2:") - 1)
          .trim();
      String choice2 = res
          .substring(res.indexOf("Choice2:") + "Choice2:".length,
              res.indexOf("Choice3:") - 1)
          .trim();
      curChoices = [choice1, choice2, "End the story"];
    } else {
      curStory = res.substring(res.indexOf("Story:") + "Story:".length).trim();
    }

    return res;
  }

  Future<String> getB64Image() async {
    try {
      final response = await http.post(
        Uri.parse(
            "$stabilityApiHost/v1/generation/$stabiltyEngineId/text-to-image"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": "Bearer ${dotenv.env["STABILITY_KEY"]!}"
        },
        body: jsonEncode({
          "text_prompts": [
            {
              "text":
                  "A first person view in the style of detailed ${artStyleOptions[chosenArtStyleIndex]} art: $curStory"
            }
          ],
          "cfg_scale": 18,
          "clip_guidance_preset": "FAST_BLUE",
          "height": 512,
          "width": 512,
          "samples": 1,
          "steps": 38,
        }),
      );
      curImage = json.decode(response.body)["artifacts"][0]["base64"];
      return curImage!;
    } catch (e) {
      curStory = null;
      curImage = null;
      setState(() {});
      return "Error";
    }
  }

  void addSection(int selectedChoiceIndex) {
    completedSections.add(CompletedSection(
        storyText: curStory!,
        base64Image: curImage!,
        choices: curChoices!,
        previousChoice: previousChoice!));
    previousChoice = curChoices![selectedChoiceIndex];
    curStory = null;
    curImage = null;
    curChoices = null;
    startGenerating = false;
    setState(() {});
  }

  void addFinalSection() {
    completedSections.add(CompletedSection(
        storyText: curStory!,
        base64Image: curImage!,
        choices: [],
        previousChoice: "End the story"));
    allSectionsCompleted = true;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Build a Story",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color.fromARGB(255, 35, 104, 161))),
      home: Scaffold(
          body: !buildStory
              ? Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          "BUILD A STORY",
                          style: GoogleFonts.lato(
                              color: const Color.fromARGB(255, 10, 110, 192),
                              fontSize: 36,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Select an Art Style:",
                            style:
                                GoogleFonts.lato(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          DropdownButton(
                              value: chosenArtStyleIndex,
                              items: [
                                for (int i = 0; i < artStyleOptions.length; i++)
                                  DropdownMenuItem(
                                    value: i,
                                    child:
                                        Text(artStyleOptions[i].toUpperCase()),
                                  )
                              ],
                              onChanged: (val) {
                                setState(() {
                                  chosenArtStyleIndex = val!;
                                });
                                FocusScope.of(context).unfocus();
                              })
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white),
                            onPressed: () {
                              buildStory = true;
                              setState(() {});
                            },
                            child: Text(
                              "START BUILDING STORY",
                              style: GoogleFonts.lato(
                                  fontWeight: FontWeight.bold,
                                  color: const Color.fromARGB(255, 10, 110, 192)),
                            )),
                      )
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                          child: Text(
                            "BUILD A STORY",
                            style: GoogleFonts.lato(
                                color: const Color.fromARGB(255, 10, 110, 192),
                                fontSize: 36,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(
                          width: double.infinity,
                        ),
                        for (final section in completedSections)
                          CompletedSectionWidget(section),
                        if (!allSectionsCompleted) buildStoryText(),
                        if (!allSectionsCompleted && startGenerating)
                          buildImage(),
                        if (allSectionsCompleted) buildVideo()
                      ]),
                )),
    );
  }

  Widget buildVideo() {
    return videoUrl != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "Here's your story:",
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(fontSize: 28),
              ),
              Container(
                  height: 500,
                  width: 500,
                  margin: const EdgeInsets.all(16),
                  child: VideoPlayerWidget(videoUrl!)),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ElevatedButton(
                    onPressed: () {
                      curChoices = null;
                      videoUrl = null;
                      buildStory = false;
                      selectedChoiceIndex = 0;
                      completedSections = [];
                      allSectionsCompleted = false;
                      startGenerating = false;
                      setState(() {});
                    },
                    child: const Text("Build Another Story")),
              )
            ],
          )
        : FutureBuilder(
            future: FirebaseFunctions.instance
                .httpsCallable("on_request_example")
                .call({
              "images": [
                for (final section in completedSections) section.base64Image
              ],
              "texts": [
                for (final section in completedSections) section.storyText
              ]
            }).then((value) {
              videoUrl = value.data["res"];
            }),
            builder: (ctx, snapshot) {
              if (snapshot.hasError) {
                return Container(
                    decoration: BoxDecoration(color: Colors.red.shade300),
                    margin: const EdgeInsets.all(16),
                    width: 500,
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        "There was an unexpected error, please reload the page.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(color: Colors.white),
                      ),
                    ));
              } else if (snapshot.connectionState == ConnectionState.done) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Here's your story:",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(fontSize: 28),
                    ),
                    Container(
                        height: 500,
                        width: 500,
                        margin: const EdgeInsets.all(16),
                        child: VideoPlayerWidget(videoUrl!)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton(
                          onPressed: () {
                            curChoices = null;
                            curStory = null;
                            curImage = null;
                            videoUrl = null;
                            buildStory = false;
                            selectedChoiceIndex = 0;
                            chosenArtStyleIndex = 0;
                            completedSections = [];
                            allSectionsCompleted = false;
                            startGenerating = false;
                            setState(() {});
                          },
                          child: const Text("Build Another Story")),
                    )
                  ],
                );
              } else {
                return Container(
                    width: 500,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        color: Colors.grey.shade300),
                    margin: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.grey.shade800,
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Text(
                          "Putting your story together",
                          style: GoogleFonts.lato(),
                        )
                      ],
                    ));
              }
            });
  }

  Widget buildImageWidget(String b64Img) {
    return Column(
      children: [
        Container(
            height: 500,
            width: 500,
            margin: const EdgeInsets.all(16),
            child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                child: Image.memory(base64Decode(b64Img)))),
        previousChoice == "End the story"
            ? Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ElevatedButton(
                    onPressed: () {
                      addFinalSection();
                      setState(() {});
                    },
                    child: const Text("Generate Video")),
              )
            : completedSections.length < 4
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "How does the story progress?",
                          style: GoogleFonts.lato(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ChoiceButton(
                          choice: curChoices![0],
                          callback: () {
                            addSection(0);
                          }),
                      ChoiceButton(
                          choice: curChoices![1],
                          callback: () {
                            addSection(1);
                          }),
                      ChoiceButton(
                          choice: "End the story",
                          callback: () {
                            addSection(2);
                          }),
                    ],
                  )
                : ChoiceButton(
                    choice: "End the story",
                    callback: () {
                      addSection(2);
                    },
                  )
      ],
    );
  }

  Widget buildImage() {
    return curImage != null
        ? buildImageWidget(curImage!)
        : FutureBuilder(
            future: getB64Image(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                    height: 500,
                    width: 500,
                    margin: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 84, 146, 197),
                        borderRadius: BorderRadius.all(Radius.circular(6))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                        const SizedBox(
                          width: 16,
                        ),
                        Text(
                          "Generating Image",
                          style: GoogleFonts.lato(color: Colors.white),
                        )
                      ],
                    ));
              } else if (snapshot.connectionState == ConnectionState.done) {
                return snapshot.data != null ? buildImageWidget(snapshot.data!) : Container();
              } else {
                return Container(
                    decoration: BoxDecoration(color: Colors.red.shade300),
                    width: 500,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        "There was an error, please try again.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(color: Colors.white),
                      ),
                    ));
              }
            });
  }

  Widget buildStoryTextWidget() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          width: 500,
          child: Text(
            curStory!,
            style: GoogleFonts.lato(),
            textAlign: TextAlign.center,
          ),
        ),
        if (!startGenerating)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton(
                onPressed: () {
                  startGenerating = true;
                  setState(() {});
                },
                child: const Text("Generate Image")),
          )
      ],
    );
  }

  Widget buildStoryText() {
    return curStory != null
        ? buildStoryTextWidget()
        : FutureBuilder(
            future: getChatResponse(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return buildStoryTextWidget();
              } else if (snapshot.hasError) {
                return Container(
                    decoration: BoxDecoration(color: Colors.red.shade300),
                    margin: const EdgeInsets.all(16),
                    width: 500,
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        "There was an error, please try again.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(color: Colors.white),
                      ),
                    ));
              } else {
                return Container(
                    width: 500,
                    margin: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 102, 178, 240),
                        borderRadius: BorderRadius.all(Radius.circular(8))),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                        const SizedBox(
                          width: 16,
                        ),
                        Text(
                          "Building next stage of story",
                          style: GoogleFonts.lato(color: Colors.white),
                        )
                      ],
                    ));
              }
            });
  }
}

class ChoiceButton extends StatelessWidget {
  const ChoiceButton({super.key, required this.choice, required this.callback});

  final String choice;
  final VoidCallback callback;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextButton(onPressed: callback, child: Text(choice)),
    );
  }
}
