//
//  ViewController.swift
//  Sound Vision
//
//  Created by Bakhtiar Temirov on 8/11/18.
//  Copyright © 2018 Bakhtiar Temirov. All rights reserved.
//

import UIKit
import CoreML
import Vision
import AVFoundation
import AudioToolbox

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var detectedText: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var morseText: UILabel!
    
    let vibration = [
        ".": AudioServicesPlaySystemSound(1520), // Weak
        "-": AudioServicesPlayAlertSound(kSystemSoundID_Vibrate),]


    let alphaNumToMorse = [
        "A": ".-",
        "B": "-...",
        "C": "-.-.",
        "D": "-..",
        "E": ".",
        "F": "..-.",
        "G": "--.",
        "H": "....",
        "I": "..",
        "J": ".---",
        "K": "-.-",
        "L": ".-..",
        "M": "--",
        "N": "-.",
        "O": "---",
        "P": ".--.",
        "Q": "--.-",
        "R": ".-.",
        "S": "...",
        "T": "-",
        "U": "..-",
        "V": "...-",
        "W": ".--",
        "X": "-..-",
        "Y": "-.--",
        "Z": "--..",
        "a": ".-",
        "b": "-...",
        "c": "-.-.",
        "d": "-..",
        "e": ".",
        "f": "..-.",
        "g": "--.",
        "h": "....",
        "i": "..",
        "j": ".---",
        "k": "-.-",
        "l": ".-..",
        "m": "--",
        "n": "-.",
        "o": "---",
        "p": ".--.",
        "q": "--.-",
        "r": ".-.",
        "s": "...",
        "t": "-",
        "u": "..-",
        "v": "...-",
        "w": ".--",
        "x": "-..-",
        "y": "-.--",
        "z": "--..",
        "1": ".----",
        "2": "..---",
        "3": "...--",
        "4": "....-",
        "5": ".....",
        "6": "-....",
        "7": "--...",
        "8": "---..",
        "9": "----.",
        "0": "-----",
        " ": " ",
        ]
    var model: VNCoreMLModel!
    let short = "."
    let long = "-"
    let space = "|"

    
    var textMetadata = [Int: [Int: String]]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadModel()
        activityIndicator.hidesWhenStopped = true
        
        
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(action))
        self.view.addGestureRecognizer(recognizer)
        
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(swipe:)))
        swipeUp.direction = UISwipeGestureRecognizer.Direction.up
        self.view.addGestureRecognizer(swipeUp)
 
    }
    
    private func loadModel() {
        model = try? VNCoreMLModel(for: Alphanum_28x28().model)
    }

    // MARK: IBAction
    
    @IBAction func pickImageClicked(_ sender: UIButton) {
        let alertController = createActionSheet()
        let action1 = UIAlertAction(title: "Camera", style: .default, handler: {
            (alert: UIAlertAction!) -> Void in
            self.showImagePicker(withType: .camera)
        })
        let action2 = UIAlertAction(title: "Photos", style: .default, handler: {
            (alert: UIAlertAction!) -> Void in
            self.showImagePicker(withType: .photoLibrary)
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        addActionsToAlertController(controller: alertController,
                                    actions: [action1, action2, cancelAction])
        self.present(alertController, animated: true, completion: nil)
    }
    
    // MARK: image picker
    
    func showImagePicker(withType type: UIImagePickerController.SourceType) {
        let pickerController = UIImagePickerController()
        pickerController.delegate = self
        pickerController.sourceType = type
        present(pickerController, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
// Local variable inserted by Swift 4.2 migrator.
let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)

        dismiss(animated: true)
        guard let image = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage else {
            fatalError("Couldn't load image")
        }
        let newImage = fixOrientation(image: image)
        self.imageView.image = newImage
        clearOldData()
        showActivityIndicator()
        DispatchQueue.global(qos: .userInteractive).async {
            self.detectText(image: newImage)
        }
    }
    
    // MARK: text detection
    
    func detectText(image: UIImage) {
        let convertedImage = image |> adjustColors |> convertToGrayscale
        let handler = VNImageRequestHandler(cgImage: convertedImage.cgImage!)
        let request: VNDetectTextRectanglesRequest =
            VNDetectTextRectanglesRequest(completionHandler: { [unowned self] (request, error) in
            if (error != nil) {
                print("Got Error In Run Text Dectect Request :(")
            } else {
                guard let results = request.results as? Array<VNTextObservation> else {
                    fatalError("Unexpected result type from VNDetectTextRectanglesRequest")
                }
                if (results.count == 0) {
                    self.handleEmptyResults()
                    return
                }
                var numberOfWords = 0
                for textObservation in results {
                    var numberOfCharacters = 0
                    for rectangleObservation in textObservation.characterBoxes! {
                        let croppedImage = crop(image: image, rectangle: rectangleObservation)
                        if let croppedImage = croppedImage {
                            let processedImage = preProcess(image: croppedImage)
                            self.classifyImage(image: processedImage,
                                               wordNumber: numberOfWords,
                                               characterNumber: numberOfCharacters)
                            numberOfCharacters += 1
                        }
                    }
                    numberOfWords += 1
                }
            }
        })
        request.reportCharacterBoxes = true
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
    }
    
    func handleEmptyResults() {
        DispatchQueue.main.async {
            self.hideActivityIndicator()
            self.detectedText.text = "The image does not contain any text."
        }
        
    }
    
    func classifyImage(image: UIImage, wordNumber: Int, characterNumber: Int) {
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation],
                let topResult = results.first else {
                    fatalError("Unexpected result type from VNCoreMLRequest")
            }
            let result = topResult.identifier
            let classificationInfo: [String: Any] = ["wordNumber" : wordNumber,
                                                     "characterNumber" : characterNumber,
                                                     "class" : result]
            self?.handleResult(classificationInfo)
        }
        guard let ciImage = CIImage(image: image) else {
            fatalError("Could not convert UIImage to CIImage :(")
        }
        let handler = VNImageRequestHandler(ciImage: ciImage)
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([request])
            }
            catch {
                print(error)
            }
        }
    }
    
    func handleResult(_ result: [String: Any]) {
        objc_sync_enter(self)
        guard let wordNumber = result["wordNumber"] as? Int else {
            return
        }
        guard let characterNumber = result["characterNumber"] as? Int else {
            return
        }
        guard let characterClass = result["class"] as? String else {
            return
        }
        if (textMetadata[wordNumber] == nil) {
            let tmp: [Int: String] = [characterNumber: characterClass]
            textMetadata[wordNumber] = tmp
        } else {
            var tmp = textMetadata[wordNumber]!
            tmp[characterNumber] = characterClass
            textMetadata[wordNumber] = tmp
        }
        objc_sync_exit(self)
        DispatchQueue.main.async {
            self.hideActivityIndicator()
            self.showDetectedText()
        }
    }
    
    func showDetectedText() {
        var result: String = ""
        if (textMetadata.isEmpty) {
            detectedText.text = "The image does not contain any text."
            return
        }
        let sortedKeys = textMetadata.keys.sorted()
        for sortedKey in sortedKeys {
            result +=  word(fromDictionary: textMetadata[sortedKey]!) + " "
        }
        detectedText.text = result
    }
    
    func word(fromDictionary dictionary: [Int : String]) -> String {
        let sortedKeys = dictionary.keys.sorted()
        var word: String = ""
        for sortedKey in sortedKeys {
            let char: String = dictionary[sortedKey]!
            word += char
        }
        return word
    }
    
    // MARK: private
    
    private func clearOldData() {
        detectedText.text = ""
        textMetadata = [:]
    }
    
    private func showActivityIndicator() {
        activityIndicator.startAnimating()
    }
    
    private func hideActivityIndicator() {
        activityIndicator.stopAnimating()
    }
    var translatedText = ""
    var abcText = ""
    
    @objc func action() {
        abcText = detectedText.text!
        for letter in abcText {
            if alphaNumToMorse.keys.contains("\(letter)") {
                translatedText += alphaNumToMorse[String(letter)]! + "|"
            }
        }
        morseText.text = translatedText
        translatedText = ""
        detectedText.textColor = UIColor.white
    }
     /*
    @objc func action() {
        var value = ""
        morseText.text = " "
        let strs = detectedText.text
        for str in strs!{
            value.append(Morse_C.trans(str: String(str)))  //translating to morse code
            value.append("|")  //using "|" symbol as a space
        }
        morseText.text = value
        detectedText.textColor = UIColor.white
        }
    
   var translatedText = ""
     var abcText = ""
     @IBAction func clikedButton(_ sender: Any) {
     abcText = enteredText.text!
     for letter in abcText {
     if alphaNumToMorse.keys.contains("\(letter)") {
     translatedText += alphaNumToMorse[String(letter)]! + " "
     }
     }
     
     @objc func swipeAction(swipe:UISwipeGestureRecognizer)
    {
     for str in morseText.text!{
     
     if str == "-"{
     AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
     }
     if str == "."{
     AudioServicesPlaySystemSound(1520); // Weak
     }
     
     
     if str == "|"{
     usleep(500000)
            }
        
    } */
    var vibeText = ""
        @objc func swipeAction(swipe:UISwipeGestureRecognizer)
    {
        vibeText = morseText.text!
        for symbol in vibeText {
            if  symbol == "."{
                AudioServicesPlaySystemSound(1520); // Weak
                sleep(1)
            }
           else  if symbol == "-"{
              AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
                sleep(1)
            }
            else if symbol == "|"{
                sleep(1)

            
        }
    
}
    


}
    /*
    var vibeText = ""
    @objc func swipeAction(swipe:UISwipeGestureRecognizer)
    {
        vibeText = morseText.text!
        for symbol in vibeText {
            if vibration.keys.contains("\(symbol)") {
                // something to write to vibrate
            }
        }
    }
*/
}


// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
	return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
