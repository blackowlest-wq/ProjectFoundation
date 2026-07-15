/**
 * ロガー用のリクエストメタデータInterceptorをMVCへ登録する。
 */
package com.example.dailyreport.observability;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class ObservabilityWebConfig implements WebMvcConfigurer {
    private final RequestMetadataInterceptor requestMetadataInterceptor = new RequestMetadataInterceptor();

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(requestMetadataInterceptor);
    }
}
