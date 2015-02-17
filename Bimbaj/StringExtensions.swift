//
//  String.swift
//  Bimbaj
//
//  Created by Bartosz Kopiński on 04/05/15.
//  Copyright (c) 2015 Bartosz Kopiński. All rights reserved.
//

import Foundation

extension String {
    func removeCharsFromEnd(count_:Int) -> String {
        let stringLength = count(self)

        let substringIndex = (stringLength < count_) ? 0 : stringLength - count_

        return self.substringToIndex(advance(self.startIndex, substringIndex))
    }
}