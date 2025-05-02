# HybridCollab

Unifying In-Person and Remote Collaboration for Cardiovascular Surgical Planning in Mobile Augmented Reality

[![MIT license](http://img.shields.io/badge/license-MIT-brightgreen.svg)](http://opensource.org/licenses/MIT)

![crown-jewel](https://github.com/user-attachments/assets/0e37fbe5-b6fb-468c-ba3b-a8e38b848297)

## What is HybridCollab?

HybridCollab is the first iOS AR application that introduces a novel paradigm that enables both in-person and remote medical teams to interact with a shared AR heart model in a single surgical planning session.

For example, a team of two doctors in one hospital room can collaborate in real time with another team in a different hospital. Our approach is the first to leverage Apple’s GameKit service for surgical planning, ensuring an identical collaborative experience for all participants, regardless of location. Additionally, co-located users can interact with the same anchored heart model in their shared physical space.

## Video Demo

Watch a video demo of HybridCollab [here](https://youtu.be/hElqJYDuvLM).

## Project Setup

To use HybridCollab, you will need to have a `obj` version of an AR heart model. Follow the instructions to setup the project.

1. Clone the repo and open the `HybridCollab.xcodeproj` file in [`Xcode`](https://developer.apple.com/xcode/).
2. Add the heart model to the project:
  a. Ensure the `obj` file is named as `heart_model.obj`
  b. Drag the file into the project directory in Xcode, under the project and the `HybridCollab` group.
3. Run the app on a physical device. (Note: you may need to change the bundle id and follow the instructions [here](https://developer.apple.com/documentation/GameKit/enabling-and-configuring-game-center) using a paid Apple Developer Account).

## Credits

HybridCollab is created by Pratham Mehta, Rahul Narayanan, Vidhi Kulkarni, and Polo Chau.

## License

The software is available under the MIT License.
