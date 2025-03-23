package com.unbumpkin.codechat.controller;

import org.springframework.boot.web.servlet.error.ErrorController;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;
import java.util.logging.Logger;

@Controller
public class CustomErrorController implements ErrorController {

    private static final Logger logger = Logger.getLogger(CustomErrorController.class.getName());

    @RequestMapping("/error")
    @ResponseBody
    public Map<String, Object> handleError(HttpServletRequest request) {
        Map<String, Object> errorAttributes = new HashMap<>();
        Object status = request.getAttribute("javax.servlet.error.status_code");
        Object message = request.getAttribute("javax.servlet.error.message");
        Object path = request.getAttribute("javax.servlet.error.request_uri");

        logger.info("Status: " + status);
        logger.info("Message: " + message);
        logger.info("Path: " + path);

        errorAttributes.put("status", status);
        errorAttributes.put("message", message);
        errorAttributes.put("path", path);
        return errorAttributes;
    }

}