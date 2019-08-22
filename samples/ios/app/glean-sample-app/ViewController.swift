//
//  ViewController.swift
//  glean-sample-app
//
//  Created by Jan-Erik Rediger on 28.03.19.
//  Copyright © 2019 Jan-Erik Rediger. All rights reserved.
//

import UIKit
import Glean
import os.log

public enum CorePing {
    static let seq = Counter(name: "seq", disabled: false)
}

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        os_log("incrementing coreping.seq")
        CorePing.seq.add()
        os_log("done incremeting coreping.seq")
    }


}

