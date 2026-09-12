package com.example.framework;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class FrameworkController {
    @GetMapping("/api/framework")
    public void framework() {
    }
}
